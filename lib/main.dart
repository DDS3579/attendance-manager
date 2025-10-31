import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Manager',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const AttendanceHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AttendanceHomePage extends StatefulWidget {
  const AttendanceHomePage({Key? key}) : super(key: key);

  @override
  State<AttendanceHomePage> createState() => _AttendanceHomePageState();
}

class _AttendanceHomePageState extends State<AttendanceHomePage> {
  late Database _database;
  List<Map<String, dynamic>> _students = [];
  Map<int, bool> _attendance = {};
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // Initialize SQLite database
  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Students table
        await db.execute('''
          CREATE TABLE students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        // Attendance table
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            is_present INTEGER NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students (id),
            UNIQUE(student_id, date)
          )
        ''');
      },
    );

    await _loadData();
  }

  // Load students and attendance for selected date
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load all students
    final students = await _database.query('students', orderBy: 'name ASC');
    
    // Load attendance for selected date
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final attendance = await _database.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [dateStr],
    );

    // Create attendance map
    final attendanceMap = <int, bool>{};
    for (var record in attendance) {
      attendanceMap[record['student_id'] as int] = 
          (record['is_present'] as int) == 1;
    }

    setState(() {
      _students = students;
      _attendance = attendanceMap;
      _isLoading = false;
    });
  }

  // Add new student
  Future<void> _addStudent() async {
    final name = _nameController.text.trim();
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a student name')),
      );
      return;
    }

    // Check for duplicates
    final existing = await _database.query(
      'students',
      where: 'name = ?',
      whereArgs: [name],
    );

    if (existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student already exists')),
      );
      return;
    }

    await _database.insert('students', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });

    _nameController.clear();
    await _loadData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $name')),
    );
  }

  // Remove student
  Future<void> _removeStudent(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Remove $name from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _database.delete('students', where: 'id = ?', whereArgs: [id]);
      await _database.delete('attendance', where: 'student_id = ?', whereArgs: [id]);
      await _loadData();
    }
  }

  // Mark attendance
  Future<void> _markAttendance(int studentId, bool isPresent) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    await _database.insert(
      'attendance',
      {
        'student_id': studentId,
        'date': dateStr,
        'is_present': isPresent ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _loadData();
  }

  // Change date
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadData();
    }
  }

  // Export attendance to CSV
  Future<void> _exportAttendance() async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final dateDisplay = DateFormat('MMMM dd, yyyy').format(_selectedDate);
      
      // Create CSV content
      String csv = 'Attendance Report - $dateDisplay\n\n';
      csv += 'Name,Status\n';

      int presentCount = 0;
      int absentCount = 0;

      for (var student in _students) {
        final id = student['id'] as int;
        final name = student['name'] as String;
        final isPresent = _attendance[id] ?? false;
        
        csv += '$name,${isPresent ? 'Present' : 'Absent'}\n';
        
        if (isPresent) {
          presentCount++;
        } else {
          absentCount++;
        }
      }

      csv += '\nSummary\n';
      csv += 'Total Students,${ _students.length}\n';
      csv += 'Present,$presentCount\n';
      csv += 'Absent,$absentCount\n';

      // Save to downloads folder
      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/attendance_$dateStr.csv';
      final file = File(path);
      await file.writeAsString(csv);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to: $path')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Attendance Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportAttendance,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Date selector
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.green.shade50,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!isToday)
                              const Text(
                                'Viewing past attendance',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _selectDate,
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Change Date'),
                      ),
                    ],
                  ),
                ),

                // Add student section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter student name...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _addStudent(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addStudent,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),

                // Student list
                Expanded(
                  child: _students.isEmpty
                      ? const Center(
                          child: Text(
                            'No students added yet.\nAdd your first student above!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _students.length,
                          itemBuilder: (context, index) {
                            final student = _students[index];
                            final id = student['id'] as int;
                            final name = student['name'] as String;
                            final isPresent = _attendance[id] ?? false;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: isPresent
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPresent
                                      ? Colors.green
                                      : Colors.grey,
                                  child: Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  isPresent ? 'Present' : 'Absent',
                                  style: TextStyle(
                                    color: isPresent
                                        ? Colors.green.shade700
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: isPresent
                                          ? null
                                          : () => _markAttendance(id, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(
                                        isPresent ? '✓ Marked' : 'Present',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _removeStudent(id, name),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Summary footer
                if (_students.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryItem(
                          'Total',
                          _students.length.toString(),
                          Colors.blue,
                        ),
                        _summaryItem(
                          'Present',
                          _attendance.values
                              .where((v) => v)
                              .length
                              .toString(),
                          Colors.green,
                        ),
                        _summaryItem(
                          'Absent',
                          (_students.length -
                                  _attendance.values.where((v) => v).length)
                              .toString(),
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _database.close();
    super.dispose();
  }
}