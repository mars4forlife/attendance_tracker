import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/location_service.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  bool _isProcessing = false;

  String _buildDateKey(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<bool> _saveAttendance(String scheduleId) async {
    if (!mounted) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final firestore = FirebaseFirestore.instance;

      final scheduleDoc =
          await firestore.collection('schedule').doc(scheduleId).get();

      if (!scheduleDoc.exists) {
        Fluttertoast.showToast(msg: 'Занятие не найдено');
        return false;
      }

      final userDoc = await firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        Fluttertoast.showToast(msg: 'Профиль студента не найден');
        return false;
      }

      final scheduleData = scheduleDoc.data()!;
      final userData = userDoc.data()!;

      final now = DateTime.now();
      final dateKey = _buildDateKey(now);

      final studentName = (userData['name'] ?? 'Студент').toString();
      final studentGroup = (userData['group'] ?? '').toString().trim();
      final subject =
          (scheduleData['subject'] ?? 'Неизвестное занятие').toString();

      final attendanceId = '${scheduleId}_${user.uid}_$dateKey';

      final attendanceRef =
          firestore.collection('attendance').doc(attendanceId);

      final existingDoc = await attendanceRef.get();

      if (existingDoc.exists) {
        Fluttertoast.showToast(
          msg: 'Вы уже отметили посещение на это занятие',
          backgroundColor: Colors.orange,
        );
        if (mounted) Navigator.pop(context);
        return true;
      }

      await attendanceRef.set({
        'scheduleId': scheduleId,
        'studentId': user.uid,
        'studentName': studentName,
        'group': studentGroup,
        'subject': subject,
        'dateKey': dateKey,
        'status': 'present',
        'method': 'qr+gps',
        'markedBy': 'student',
        'timestamp': FieldValue.serverTimestamp(),
      });

      Fluttertoast.showToast(
        msg: 'Посещение успешно отмечено! ✅',
        backgroundColor: Colors.green,
      );

      if (mounted) {
        Navigator.pop(context);
      }

      return true;
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Ошибка сохранения: $e',
        backgroundColor: Colors.red,
      );
      return false;
    }
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;

    _isProcessing = true;

    final barcode = capture.barcodes.first;
    final scheduleId = barcode.rawValue;

    if (scheduleId == null || scheduleId.isEmpty) {
      Fluttertoast.showToast(msg: 'Неверный QR-код');
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      return;
    }

    final inZone = await LocationService.isInUniversityZone();

    if (!inZone) {
      Fluttertoast.showToast(
        msg: 'Вы не находитесь в зоне университета',
        backgroundColor: Colors.red,
      );
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      return;
    }

    final isSaved = await _saveAttendance(scheduleId);

    if (!isSaved && mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканирование QR-кода'),
      ),
      body: MobileScanner(
        onDetect: _handleDetection,
      ),
    );
  }
}
