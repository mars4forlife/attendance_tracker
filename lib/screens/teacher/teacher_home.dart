import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TeacherHome extends StatelessWidget {
  const TeacherHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Преподаватель"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text("Преподаватель не найден"));
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          final teacherName = userData['name'] ?? 'Преподаватель';

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.indigo.shade100,
                        child: const Icon(
                          Icons.person,
                          size: 32,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              teacherName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Преподаватель",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('schedule')
                      .where('teacherId', isEqualTo: user.uid)
                      .orderBy('dayOfWeek')
                      .orderBy('startTime')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "У вас пока нет пар.\nПопросите администратора добавить расписание.",
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final schedules = snapshot.data!.docs;
                    final Map<int, List<QueryDocumentSnapshot>>
                        groupedSchedules = {};

                    for (var doc in schedules) {
                      final data = doc.data() as Map<String, dynamic>;
                      final day = data['dayOfWeek'] ?? 1;
                      groupedSchedules.putIfAbsent(day, () => []).add(doc);
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: groupedSchedules.entries.map((entry) {
                        final day = entry.key;
                        final lessons = entry.value;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _getDayName(day),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                            ...lessons.map((lessonDoc) {
                              final data =
                                  lessonDoc.data() as Map<String, dynamic>;
                              final scheduleId = lessonDoc.id;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.indigo.shade50,
                                    child: const Icon(
                                      Icons.menu_book,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                  title: Text(
                                    data['subject'] ?? 'Без названия',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      "${data['startTime']} - ${data['endTime']}\n"
                                      "Группа: ${data['group'] ?? '—'}",
                                    ),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios,
                                      size: 18),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TeacherLessonScreen(
                                          scheduleId: scheduleId,
                                          subject:
                                              data['subject'] ?? 'Без названия',
                                          group: data['group'] ?? '',
                                          startTime: data['startTime'] ?? '',
                                          endTime: data['endTime'] ?? '',
                                          teacherId: user.uid,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
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
        return "";
    }
  }
}

class TeacherLessonScreen extends StatelessWidget {
  final String scheduleId;
  final String subject;
  final String group;
  final String startTime;
  final String endTime;
  final String teacherId;

  const TeacherLessonScreen({
    super.key,
    required this.scheduleId,
    required this.subject,
    required this.group,
    required this.startTime,
    required this.endTime,
    required this.teacherId,
  });

  String _buildDateKey(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _markStudentManually({
    required String studentId,
    required String studentName,
  }) async {
    try {
      final dateKey = _buildDateKey(DateTime.now());
      final attendanceId = '${scheduleId}_${studentId}_$dateKey';

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendanceId)
          .set({
        'scheduleId': scheduleId,
        'studentId': studentId,
        'studentName': studentName,
        'group': group,
        'subject': subject,
        'dateKey': dateKey,
        'status': 'manual',
        'method': 'manual',
        'markedBy': teacherId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      Fluttertoast.showToast(
        msg: 'Студент отмечен вручную',
        backgroundColor: Colors.green,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Ошибка ручной отметки: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _removeAttendance(String studentId) async {
    try {
      final dateKey = _buildDateKey(DateTime.now());
      final attendanceId = '${scheduleId}_${studentId}_$dateKey';

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendanceId)
          .delete();

      Fluttertoast.showToast(
        msg: 'Отметка удалена',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Ошибка удаления: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = _buildDateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Управление занятием"),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    subject,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text("Группа: $group"),
                  Text("Время: $startTime - $endTime"),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: scheduleId,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'student')
                  .where('group', isEqualTo: group)
                  .orderBy('name')
                  .snapshots(),
              builder: (context, studentsSnapshot) {
                if (studentsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!studentsSnapshot.hasData ||
                    studentsSnapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("В этой группе нет студентов"),
                  );
                }

                final students = studentsSnapshot.data!.docs;

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('attendance')
                      .where('scheduleId', isEqualTo: scheduleId)
                      .where('dateKey', isEqualTo: dateKey)
                      .snapshots(),
                  builder: (context, attendanceSnapshot) {
                    if (attendanceSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final attendanceDocs = attendanceSnapshot.data?.docs ?? [];

                    final Map<String, Map<String, dynamic>> attendanceMap = {
                      for (var doc in attendanceDocs)
                        (doc.data() as Map<String, dynamic>)['studentId']:
                            doc.data() as Map<String, dynamic>
                    };

                    final presentCount = attendanceMap.length;
                    final totalCount = students.length;
                    final absentCount = totalCount - presentCount;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  title: 'Всего',
                                  value: totalCount.toString(),
                                  color: Colors.blue,
                                ),
                              ),
                              Expanded(
                                child: _StatCard(
                                  title: 'Отмечены',
                                  value: presentCount.toString(),
                                  color: Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _StatCard(
                                  title: 'Отсутствуют',
                                  value: absentCount.toString(),
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: students.length,
                            itemBuilder: (context, index) {
                              final studentDoc = students[index];
                              final studentData =
                                  studentDoc.data() as Map<String, dynamic>;
                              final studentId = studentDoc.id;
                              final studentName =
                                  studentData['name'] ?? 'Без имени';

                              final attendance = attendanceMap[studentId];
                              final isPresent = attendance != null;
                              final method = attendance?['method'];
                              final status = attendance?['status'];

                              Color statusColor;
                              String statusText;

                              if (!isPresent) {
                                statusColor = Colors.red;
                                statusText = 'Отсутствует';
                              } else if (method == 'manual' ||
                                  status == 'manual') {
                                statusColor = Colors.orange;
                                statusText = 'Вручную';
                              } else {
                                statusColor = Colors.green;
                                statusText = 'По QR';
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        statusColor.withOpacity(0.15),
                                    child: Icon(
                                      isPresent ? Icons.check : Icons.close,
                                      color: statusColor,
                                    ),
                                  ),
                                  title: Text(
                                    studentName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(statusText),
                                  trailing: isPresent
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            _removeAttendance(studentId);
                                          },
                                        )
                                      : ElevatedButton(
                                          onPressed: () {
                                            _markStudentManually(
                                              studentId: studentId,
                                              studentName: studentName,
                                            );
                                          },
                                          child: const Text("Отметить"),
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
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
