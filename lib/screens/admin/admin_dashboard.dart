import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Панель Администратора"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Пользователи"),
            Tab(text: "Расписание"),
            Tab(text: "Посещаемость"),
            Tab(text: "Статистика"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UsersTab(),
          _ScheduleTab(),
          _AttendanceTab(),
          _AnalyticsTab(),
        ],
      ),
    );
  }
}

class _AnalyticsTab extends StatefulWidget {
  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  DateTime _selectedDate = DateTime.now();

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadRelatedData(
    List<QueryDocumentSnapshot> attendanceDocs,
  ) async {
    final studentIds = attendanceDocs
        .map((doc) => (doc.data() as Map)['studentId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final lessonIds = attendanceDocs
        .map((doc) => (doc.data() as Map)['lessonId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> usersMap = {};
    final Map<String, Map<String, dynamic>> scheduleMap = {};

    for (final studentId in studentIds) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .get();

      if (userDoc.exists) {
        usersMap[studentId] = userDoc.data() ?? {};
      }
    }

    for (final lessonId in lessonIds) {
      final lessonDoc = await FirebaseFirestore.instance
          .collection('schedule')
          .doc(lessonId)
          .get();

      if (lessonDoc.exists) {
        scheduleMap[lessonId] = lessonDoc.data() ?? {};
      }
    }

    return {
      'users': usersMap,
      'schedule': scheduleMap,
    };
  }

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    final endOfDay = startOfDay.add(const Duration(days: 1));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where(
              'timestamp',
              isLessThan: Timestamp.fromDate(endOfDay),
            )
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, attendanceSnapshot) {
          if (attendanceSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!attendanceSnapshot.hasData ||
              attendanceSnapshot.data!.docs.isEmpty) {
            return Column(
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.analytics, color: Colors.indigo),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Статистика посещаемости",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_formatDate(_selectedDate)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Expanded(
                  child: Center(
                    child: Text("За выбранную дату посещений нет"),
                  ),
                ),
              ],
            );
          }

          final attendanceDocs = attendanceSnapshot.data!.docs;

          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _loadRelatedData(attendanceDocs),
            builder: (context, relatedSnapshot) {
              if (relatedSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!relatedSnapshot.hasData) {
                return const Center(
                  child: Text("Не удалось загрузить связанные данные"),
                );
              }

              final usersMap = relatedSnapshot.data!['users'] ?? {};
              final scheduleMap = relatedSnapshot.data!['schedule'] ?? {};

              final enriched = attendanceDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final studentId = data['studentId']?.toString() ?? '';
                final lessonId = data['lessonId']?.toString() ?? '';

                final userData = usersMap[studentId] ?? {};
                final lessonData = scheduleMap[lessonId] ?? {};

                return {
                  'studentId': studentId,
                  'studentName': userData['name']?.toString() ?? 'Без имени',
                  'group': userData['group']?.toString() ??
                      lessonData['group']?.toString() ??
                      '—',
                  'subject': data['subject']?.toString() ??
                      lessonData['subject']?.toString() ??
                      'Неизвестное занятие',
                };
              }).toList();

              final uniqueStudents = enriched
                  .map((e) => e['studentId']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .length;

              final uniqueGroups = enriched
                  .map((e) => e['group']?.toString() ?? '')
                  .where((g) => g.isNotEmpty && g != '—')
                  .toSet()
                  .length;

              final uniqueSubjects = enriched
                  .map((e) => e['subject']?.toString() ?? '')
                  .where((s) => s.isNotEmpty && s != '—')
                  .toSet()
                  .length;

              final Map<String, int> groupStats = {};
              final Map<String, int> subjectStats = {};

              for (final item in enriched) {
                final group = item['group']?.toString() ?? '—';
                final subject = item['subject']?.toString() ?? '—';

                groupStats[group] = (groupStats[group] ?? 0) + 1;
                subjectStats[subject] = (subjectStats[subject] ?? 0) + 1;
              }

              final sortedGroups = groupStats.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              final sortedSubjects = subjectStats.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return ListView(
                children: [
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.analytics, color: Colors.indigo),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Статистика посещаемости",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(_formatDate(_selectedDate)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatCard(
                        label: "Всего записей",
                        value: attendanceDocs.length.toString(),
                        icon: Icons.fact_check,
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: "Студентов",
                        value: uniqueStudents.toString(),
                        icon: Icons.people,
                        color: Colors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatCard(
                        label: "Групп",
                        value: uniqueGroups.toString(),
                        icon: Icons.groups,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: "Предметов",
                        value: uniqueSubjects.toString(),
                        icon: Icons.menu_book,
                        color: Colors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Топ групп",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sortedGroups.take(5).map((entry) {
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade100,
                          child: const Icon(Icons.groups, color: Colors.orange),
                        ),
                        title: Text(entry.key),
                        trailing: Text(
                          "${entry.value} отметок",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Text(
                    "Топ предметов",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sortedSubjects.take(5).map((entry) {
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(Icons.book, color: Colors.indigo),
                        ),
                        title: Text(entry.key),
                        trailing: Text(
                          "${entry.value} отметок",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ВКЛАДКА ПОЛЬЗОВАТЕЛИ ====================
class _UsersTab extends StatefulWidget {
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _groupController = TextEditingController();

  final _searchController = TextEditingController();

  String _selectedRole = 'student';
  String _roleFilter = 'Все';
  String _searchQuery = '';

  bool _isLoading = false;

  final List<String> _roles = ['student', 'teacher', 'admin'];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _groupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: "Заполните обязательные поля");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final User? currentAdmin = FirebaseAuth.instance.currentUser;

      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': _selectedRole,
        'group': _selectedRole == 'student' &&
                _groupController.text.trim().isNotEmpty
            ? _groupController.text.trim()
            : null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseAuth.instance.signOut();

      if (currentAdmin != null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: currentAdmin.email!,
          password: "123456",
        );
      }

      Fluttertoast.showToast(msg: "Пользователь успешно создан");

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _groupController.clear();

      setState(() {
        _selectedRole = 'student';
      });
    } catch (e) {
      Fluttertoast.showToast(msg: "Ошибка: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditUserDialog(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    final groupController = TextEditingController(
      text: data['group']?.toString() ?? '',
    );

    String selectedRole = data['role']?.toString() ?? 'student';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text("Редактировать пользователя"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Полное имя",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: "Роль",
                        border: OutlineInputBorder(),
                      ),
                      items: _roles.map((role) {
                        String label = role == 'student'
                            ? 'Студент'
                            : role == 'teacher'
                                ? 'Преподаватель'
                                : 'Администратор';
                        return DropdownMenuItem<String>(
                          value: role,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setModalState(() {
                          selectedRole = value ?? 'student';
                          if (selectedRole != 'student') {
                            groupController.clear();
                          }
                        });
                      },
                    ),
                    if (selectedRole == 'student') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: groupController,
                        decoration: const InputDecoration(
                          labelText: "Группа",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Отмена"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      Fluttertoast.showToast(msg: "Имя не может быть пустым");
                      return;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(docId)
                          .update({
                        'name': nameController.text.trim(),
                        'role': selectedRole,
                        'group': selectedRole == 'student' &&
                                groupController.text.trim().isNotEmpty
                            ? groupController.text.trim()
                            : null,
                      });

                      Navigator.pop(context, true);
                    } catch (e) {
                      Fluttertoast.showToast(
                        msg: "Ошибка обновления: $e",
                      );
                    }
                  },
                  child: const Text("Сохранить"),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      Fluttertoast.showToast(msg: "Пользователь обновлен");
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'student':
        return 'Студент';
      case 'teacher':
        return 'Преподаватель';
      case 'admin':
        return 'Администратор';
      default:
        return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'student':
        return Colors.blue;
      case 'teacher':
        return Colors.green;
      case 'admin':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Создать нового пользователя",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: "Полное имя *",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: "Email *",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Пароль *",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedRole,
                          decoration: const InputDecoration(
                            labelText: "Роль *",
                            border: OutlineInputBorder(),
                          ),
                          items: _roles.map((role) {
                            return DropdownMenuItem<String>(
                              value: role,
                              child: Text(_roleLabel(role)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedRole = value ?? 'student';
                              if (_selectedRole != 'student') {
                                _groupController.clear();
                              }
                            });
                          },
                        ),
                        if (_selectedRole == 'student') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _groupController,
                            decoration: const InputDecoration(
                              labelText: "Группа",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createUser,
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text("Создать пользователя"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.manage_accounts, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text(
                              "Управление пользователями",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: "Поиск по имени",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.trim().toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _roleFilter,
                          decoration: const InputDecoration(
                            labelText: "Фильтр по роли",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Все',
                              child: Text('Все роли'),
                            ),
                            DropdownMenuItem(
                              value: 'student',
                              child: Text('Студенты'),
                            ),
                            DropdownMenuItem(
                              value: 'teacher',
                              child: Text('Преподаватели'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Администраторы'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _roleFilter = value ?? 'Все';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Список пользователей",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text("Пользователей пока нет"),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name']?.toString().toLowerCase() ?? '';
                      final role = data['role']?.toString() ?? '';

                      final matchesSearch =
                          _searchQuery.isEmpty || name.contains(_searchQuery);
                      final matchesRole =
                          _roleFilter == 'Все' || role == _roleFilter;

                      return matchesSearch && matchesRole;
                    }).toList();

                    if (docs.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child:
                                Text("По заданным фильтрам ничего не найдено"),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final role = data['role']?.toString() ?? '';
                        final group = data['group']?.toString();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor:
                                  _roleColor(role).withOpacity(0.15),
                              child: Icon(
                                role == 'student'
                                    ? Icons.school
                                    : role == 'teacher'
                                        ? Icons.person
                                        : Icons.admin_panel_settings,
                                color: _roleColor(role),
                              ),
                            ),
                            title: Text(
                              data['name']?.toString() ?? 'Без имени',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                "Email: ${data['email'] ?? '—'}\n"
                                "Роль: ${_roleLabel(role)}"
                                "${role == 'student' ? '\nГруппа: ${group ?? '—'}' : ''}",
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: "Редактировать",
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.orange,
                              ),
                              onPressed: () => _showEditUserDialog(
                                doc.id,
                                data,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ВКЛАДКА РАСПИСАНИЕ ====================
class _ScheduleTab extends StatefulWidget {
  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> {
  final _subjectController = TextEditingController();
  final _groupController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();

  String? _selectedTeacherId;
  int _selectedDay = 1;
  bool _isLoading = false;

  List<Map<String, String>> _teachers = [];

  String _groupFilter = '';
  String _teacherFilter = 'Все';

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _groupController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .get();

    setState(() {
      _teachers = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? 'Без имени',
        };
      }).toList();
    });
  }

  Future<void> _createSchedule() async {
    if (_subjectController.text.trim().isEmpty ||
        _groupController.text.trim().isEmpty ||
        _startTimeController.text.trim().isEmpty ||
        _endTimeController.text.trim().isEmpty ||
        _selectedTeacherId == null) {
      Fluttertoast.showToast(
        msg: "Заполните все поля и выберите преподавателя",
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('schedule').add({
        'subject': _subjectController.text.trim(),
        'teacherId': _selectedTeacherId,
        'group': _groupController.text.trim(),
        'dayOfWeek': _selectedDay,
        'startTime': _startTimeController.text.trim(),
        'endTime': _endTimeController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      Fluttertoast.showToast(msg: "Пара добавлена в расписание");

      _subjectController.clear();
      _groupController.clear();
      _startTimeController.clear();
      _endTimeController.clear();

      setState(() {
        _selectedTeacherId = null;
        _selectedDay = 1;
      });
    } catch (e) {
      Fluttertoast.showToast(msg: "Ошибка: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSchedule(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Удалить пару"),
          content: const Text(
            "Вы уверены, что хотите удалить эту запись из расписания?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Удалить"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('schedule')
          .doc(docId)
          .delete();
      Fluttertoast.showToast(msg: "Пара удалена");
    } catch (e) {
      Fluttertoast.showToast(msg: "Ошибка удаления: $e");
    }
  }

  Future<void> _showEditDialog(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final subjectController = TextEditingController(
      text: data['subject']?.toString() ?? '',
    );
    final groupController = TextEditingController(
      text: data['group']?.toString() ?? '',
    );
    final startTimeController = TextEditingController(
      text: data['startTime']?.toString() ?? '',
    );
    final endTimeController = TextEditingController(
      text: data['endTime']?.toString() ?? '',
    );

    String? selectedTeacherId = data['teacherId']?.toString();
    int selectedDay = (data['dayOfWeek'] ?? 1) as int;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text("Редактировать пару"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: "Предмет",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: groupController,
                      decoration: const InputDecoration(
                        labelText: "Группа",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedTeacherId,
                      decoration: const InputDecoration(
                        labelText: "Преподаватель",
                        border: OutlineInputBorder(),
                      ),
                      items: _teachers.map((teacher) {
                        return DropdownMenuItem<String>(
                          value: teacher['id'],
                          child: Text(teacher['name'] ?? 'Без имени'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setModalState(() {
                          selectedTeacherId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedDay,
                      decoration: const InputDecoration(
                        labelText: "День недели",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text("Понедельник")),
                        DropdownMenuItem(value: 2, child: Text("Вторник")),
                        DropdownMenuItem(value: 3, child: Text("Среда")),
                        DropdownMenuItem(value: 4, child: Text("Четверг")),
                        DropdownMenuItem(value: 5, child: Text("Пятница")),
                        DropdownMenuItem(value: 6, child: Text("Суббота")),
                        DropdownMenuItem(value: 7, child: Text("Воскресенье")),
                      ],
                      onChanged: (value) {
                        setModalState(() {
                          selectedDay = value ?? 1;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startTimeController,
                      decoration: const InputDecoration(
                        labelText: "Начало (08:30)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endTimeController,
                      decoration: const InputDecoration(
                        labelText: "Конец (10:00)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Отмена"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (subjectController.text.trim().isEmpty ||
                        groupController.text.trim().isEmpty ||
                        startTimeController.text.trim().isEmpty ||
                        endTimeController.text.trim().isEmpty ||
                        selectedTeacherId == null) {
                      Fluttertoast.showToast(msg: "Заполните все поля");
                      return;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection('schedule')
                          .doc(docId)
                          .update({
                        'subject': subjectController.text.trim(),
                        'group': groupController.text.trim(),
                        'teacherId': selectedTeacherId,
                        'dayOfWeek': selectedDay,
                        'startTime': startTimeController.text.trim(),
                        'endTime': endTimeController.text.trim(),
                      });

                      Navigator.pop(context, true);
                    } catch (e) {
                      Fluttertoast.showToast(msg: "Ошибка обновления: $e");
                    }
                  },
                  child: const Text("Сохранить"),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      Fluttertoast.showToast(msg: "Расписание обновлено");
    }
  }

  String _getDayName(int day) {
    switch (day) {
      case 1:
        return "Понедельник";
      case 2:
        return "Вторник";
      case 3:
        return "Среда";
      case 4:
        return "Четверг";
      case 5:
        return "Пятница";
      case 6:
        return "Суббота";
      case 7:
        return "Воскресенье";
      default:
        return "Неизвестно";
    }
  }

  String _getTeacherName(String teacherId) {
    final teacher = _teachers.cast<Map<String, String>?>().firstWhere(
          (t) => t?['id'] == teacherId,
          orElse: () => null,
        );

    return teacher?['name'] ?? 'Неизвестный преподаватель';
  }

  @override
  Widget build(BuildContext context) {
    final teacherFilterItems = [
      const DropdownMenuItem<String>(
        value: 'Все',
        child: Text('Все преподаватели'),
      ),
      ..._teachers.map(
        (teacher) => DropdownMenuItem<String>(
          value: teacher['id'],
          child: Text(teacher['name'] ?? 'Без имени'),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Добавить пару в расписание",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _subjectController,
                          decoration: const InputDecoration(
                            labelText: "Предмет *",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _groupController,
                          decoration: const InputDecoration(
                            labelText: "Группа *",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedTeacherId,
                          decoration: const InputDecoration(
                            labelText: "Преподаватель *",
                            border: OutlineInputBorder(),
                          ),
                          items: _teachers.map((teacher) {
                            return DropdownMenuItem<String>(
                              value: teacher['id'],
                              child: Text(teacher['name'] ?? 'Без имени'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedTeacherId = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _selectedDay,
                          decoration: const InputDecoration(
                            labelText: "День недели *",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 1, child: Text("Понедельник")),
                            DropdownMenuItem(value: 2, child: Text("Вторник")),
                            DropdownMenuItem(value: 3, child: Text("Среда")),
                            DropdownMenuItem(value: 4, child: Text("Четверг")),
                            DropdownMenuItem(value: 5, child: Text("Пятница")),
                            DropdownMenuItem(value: 6, child: Text("Суббота")),
                            DropdownMenuItem(
                                value: 7, child: Text("Воскресенье")),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedDay = value ?? 1);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _startTimeController,
                                decoration: const InputDecoration(
                                  labelText: "Начало (08:30) *",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _endTimeController,
                                decoration: const InputDecoration(
                                  labelText: "Конец (10:00) *",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createSchedule,
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text("Добавить в расписание"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.filter_list, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text(
                              "Фильтры",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: "Фильтр по группе",
                            prefixIcon: Icon(Icons.groups),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _groupFilter = value.trim().toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _teacherFilter,
                          decoration: const InputDecoration(
                            labelText: "Фильтр по преподавателю",
                            border: OutlineInputBorder(),
                          ),
                          items: teacherFilterItems,
                          onChanged: (value) {
                            setState(() {
                              _teacherFilter = value ?? 'Все';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Список всех пар",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('schedule')
                      .orderBy('dayOfWeek')
                      .orderBy('startTime')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text("Расписание пока пустое"),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final group =
                          data['group']?.toString().toLowerCase() ?? '';
                      final teacherId = data['teacherId']?.toString() ?? '';

                      final matchesGroup =
                          _groupFilter.isEmpty || group.contains(_groupFilter);
                      final matchesTeacher = _teacherFilter == 'Все' ||
                          teacherId == _teacherFilter;

                      return matchesGroup && matchesTeacher;
                    }).toList();

                    if (docs.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child:
                                Text("По выбранным фильтрам ничего не найдено"),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final teacherId = data['teacherId']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              child: const Icon(
                                Icons.schedule,
                                color: Colors.indigo,
                              ),
                            ),
                            title: Text(
                              data['subject']?.toString() ?? 'Без названия',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                "Группа: ${data['group'] ?? '—'}\n"
                                "Преподаватель: ${_getTeacherName(teacherId)}\n"
                                "День: ${_getDayName((data['dayOfWeek'] ?? 1) as int)}\n"
                                "Время: ${data['startTime'] ?? '--:--'} - ${data['endTime'] ?? '--:--'}",
                              ),
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: "Редактировать",
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.orange,
                                  ),
                                  onPressed: () => _showEditDialog(
                                    doc.id,
                                    data,
                                  ),
                                ),
                                IconButton(
                                  tooltip: "Удалить",
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteSchedule(doc.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ВКЛАДКА ПОСЕЩАЕМОСТЬ ====================
class _AttendanceTab extends StatefulWidget {
  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  DateTime _selectedDate = DateTime.now();
  String _selectedGroup = 'Все';
  String _selectedSubject = 'Все';
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    final endOfDay = startOfDay.add(const Duration(days: 1));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fact_check, color: Colors.indigo),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "База посещаемости",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_formatDate(_selectedDate)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: "Поиск по имени студента",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where(
                    'timestamp',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
                  )
                  .where(
                    'timestamp',
                    isLessThan: Timestamp.fromDate(endOfDay),
                  )
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, attendanceSnapshot) {
                if (attendanceSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!attendanceSnapshot.hasData ||
                    attendanceSnapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("За выбранную дату посещений нет"),
                  );
                }

                final attendanceDocs = attendanceSnapshot.data!.docs;

                return FutureBuilder<Map<String, dynamic>>(
                  future: _loadRelatedData(attendanceDocs),
                  builder: (context, relatedSnapshot) {
                    if (relatedSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!relatedSnapshot.hasData) {
                      return const Center(
                        child: Text("Не удалось загрузить связанные данные"),
                      );
                    }

                    final usersMap =
                        relatedSnapshot.data!['users'] as Map<String, dynamic>;
                    final scheduleMap = relatedSnapshot.data!['schedule']
                        as Map<String, dynamic>;

                    final enriched = attendanceDocs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final studentId = data['studentId']?.toString() ?? '';
                      final lessonId = data['lessonId']?.toString() ?? '';

                      final userData =
                          (usersMap[studentId] as Map<String, dynamic>?) ?? {};
                      final lessonData =
                          (scheduleMap[lessonId] as Map<String, dynamic>?) ??
                              {};

                      final studentName =
                          userData['name']?.toString() ?? 'Без имени';
                      final group = userData['group']?.toString() ??
                          lessonData['group']?.toString() ??
                          '—';
                      final subject = data['subject']?.toString() ??
                          lessonData['subject']?.toString() ??
                          'Неизвестное занятие';
                      final method = data['method']?.toString() ?? '—';
                      final timestamp = data['timestamp'] as Timestamp?;

                      return {
                        'id': doc.id,
                        'studentId': studentId,
                        'studentName': studentName,
                        'group': group,
                        'subject': subject,
                        'method': method,
                        'timestamp': timestamp,
                      };
                    }).toList();

                    final groups = {
                      'Все',
                      ...enriched
                          .map((e) => e['group']?.toString() ?? '—')
                          .where((g) => g.isNotEmpty),
                    }.toList()
                      ..sort();

                    final subjects = {
                      'Все',
                      ...enriched
                          .map((e) => e['subject']?.toString() ?? '—')
                          .where((s) => s.isNotEmpty),
                    }.toList()
                      ..sort();

                    if (!groups.contains(_selectedGroup)) {
                      _selectedGroup = 'Все';
                    }
                    if (!subjects.contains(_selectedSubject)) {
                      _selectedSubject = 'Все';
                    }

                    final filtered = enriched.where((item) {
                      final name =
                          item['studentName']?.toString().toLowerCase() ?? '';
                      final group = item['group']?.toString() ?? '';
                      final subject = item['subject']?.toString() ?? '';

                      final matchesSearch =
                          _searchQuery.isEmpty || name.contains(_searchQuery);
                      final matchesGroup =
                          _selectedGroup == 'Все' || group == _selectedGroup;
                      final matchesSubject = _selectedSubject == 'Все' ||
                          subject == _selectedSubject;

                      return matchesSearch && matchesGroup && matchesSubject;
                    }).toList();

                    final uniqueStudents = filtered
                        .map((e) => e['studentId']?.toString() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toSet()
                        .length;

                    return Column(
                      children: [
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedGroup,
                                        decoration: const InputDecoration(
                                          labelText: "Группа",
                                          border: OutlineInputBorder(),
                                        ),
                                        items: groups.map((group) {
                                          return DropdownMenuItem(
                                            value: group,
                                            child: Text(group),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedGroup = value ?? 'Все';
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedSubject,
                                        decoration: const InputDecoration(
                                          labelText: "Предмет",
                                          border: OutlineInputBorder(),
                                        ),
                                        items: subjects.map((subject) {
                                          return DropdownMenuItem(
                                            value: subject,
                                            child: Text(subject),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedSubject = value ?? 'Все';
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _StatChip(
                                      label: "Всего записей",
                                      value: filtered.length.toString(),
                                      color: Colors.indigo,
                                    ),
                                    const SizedBox(width: 8),
                                    _StatChip(
                                      label: "Студентов",
                                      value: uniqueStudents.toString(),
                                      color: Colors.green,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    "По выбранным фильтрам ничего не найдено",
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    final timestamp =
                                        item['timestamp'] as Timestamp?;
                                    final dt = timestamp?.toDate();

                                    final timeText = dt == null
                                        ? 'Время неизвестно'
                                        : '${dt.day.toString().padLeft(2, '0')}.'
                                            '${dt.month.toString().padLeft(2, '0')}.'
                                            '${dt.year} '
                                            '${dt.hour.toString().padLeft(2, '0')}:'
                                            '${dt.minute.toString().padLeft(2, '0')}';

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.all(12),
                                        leading: CircleAvatar(
                                          backgroundColor:
                                              Colors.green.shade100,
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          ),
                                        ),
                                        title: Text(
                                          item['studentName']?.toString() ??
                                              'Без имени',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'Группа: ${item['group']}\n'
                                            'Предмет: ${item['subject']}\n'
                                            'Метод: ${item['method']}\n'
                                            'Время: $timeText',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _loadRelatedData(
    List<QueryDocumentSnapshot> attendanceDocs,
  ) async {
    final studentIds = attendanceDocs
        .map((doc) =>
            (doc.data() as Map<String, dynamic>)['studentId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final lessonIds = attendanceDocs
        .map((doc) =>
            (doc.data() as Map<String, dynamic>)['lessonId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, dynamic> usersMap = {};
    final Map<String, dynamic> scheduleMap = {};

    for (final studentId in studentIds) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .get();

      if (userDoc.exists) {
        usersMap[studentId] = userDoc.data();
      }
    }

    for (final lessonId in lessonIds) {
      final lessonDoc = await FirebaseFirestore.instance
          .collection('schedule')
          .doc(lessonId)
          .get();

      if (lessonDoc.exists) {
        scheduleMap[lessonId] = lessonDoc.data();
      }
    }

    return {
      'users': usersMap,
      'schedule': scheduleMap,
    };
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
