import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../utils/constants.dart';
import 'scan_qr_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  int _currentIndex = 0;
  bool _isInUniversityZone = false;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Fluttertoast.showToast(msg: "Включите геолокацию");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Fluttertoast.showToast(msg: "Нет разрешения на геолокацию");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        AppConstants.universityLat,
        AppConstants.universityLng,
      );

      setState(() {
        _isInUniversityZone = distance <= AppConstants.attendanceRadiusMeters;
      });
    } catch (e) {
      debugPrint("Ошибка геолокации: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Студент"),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _checkLocation),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Статус геолокации
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isInUniversityZone
                ? Colors.green.shade100
                : Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    _isInUniversityZone
                        ? Icons.location_on
                        : Icons.location_off,
                    color: _isInUniversityZone ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(
                  _isInUniversityZone
                      ? "Вы в зоне университета ✅"
                      : "Вы вне зоны университета",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _isInUniversityZone
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                const ScheduleTab(),
                ScanAttendanceTab(isInZone: _isInUniversityZone),
                const HistoryTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.schedule), label: "Расписание"),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: "Отметить"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "История"),
        ],
      ),
    );
  }
}

// ==================== РАСПИСАНИЕ ====================
class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final studentName = userData?['name'] ?? 'Студент';
        final studentGroup = userData?['group']?.toString().trim() ?? '';

        return Column(
          children: [
            // Шапка студента (как у преподавателя)
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
                            studentName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Группа: $studentGroup",
                            style: const TextStyle(
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

            // Расписание с группировкой по дням
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('schedule')
                    .where('group', isEqualTo: studentGroup)
                    .orderBy('dayOfWeek')
                    .orderBy('startTime')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        "Расписание для группы $studentGroup пока пустое",
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final schedules = snapshot.data!.docs;

                  // Группировка по дням
                  final Map<int, List<QueryDocumentSnapshot>> grouped = {};
                  for (var doc in schedules) {
                    final day = doc['dayOfWeek'] as int;
                    grouped.putIfAbsent(day, () => []).add(doc);
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: grouped.length,
                    itemBuilder: (context, index) {
                      final day = grouped.keys.elementAt(index);
                      final daySchedules = grouped[day]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                            child: Text(
                              _getDayName(day),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          ...daySchedules.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.indigo.shade50,
                                  child: const Icon(Icons.book,
                                      color: Colors.indigo),
                                ),
                                title: Text(
                                  data['subject'] ?? 'Без названия',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  "${data['startTime']} - ${data['endTime']}",
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
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

// ==================== ИСТОРИЯ ПОСЕЩЕНИЙ (С НАЗВАНИЕМ ЗАНЯТИЯ) ====================
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('studentId', isEqualTo: user!.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 80, color: Colors.grey),
                SizedBox(height: 16),
                Text("История посещений пуста", style: TextStyle(fontSize: 18)),
              ],
            ),
          );
        }

        final attendances = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: attendances.length,
          itemBuilder: (context, index) {
            final data = attendances[index].data() as Map<String, dynamic>;
            final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 32),
                ),
                title: Text(
                  data['subject'] ?? data['lessonId'] ?? 'Занятие',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text(
                  timestamp != null
                      ? "${timestamp.day}.${timestamp.month}.${timestamp.year}   ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}"
                      : 'Время неизвестно',
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Присутствовал",
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ScanAttendanceTab extends StatelessWidget {
  final bool isInZone;

  const ScanAttendanceTab({
    super.key,
    required this.isInZone,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 100,
              color: isInZone ? Colors.indigo : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              isInZone
                  ? "Готовы отметить посещение?"
                  : "Сначала зайдите в зону университета",
              style: TextStyle(
                fontSize: 18,
                color: isInZone ? Colors.black : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: isInZone
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScanQrScreen(),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text(
                "Сканировать QR-код",
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
