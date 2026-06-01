import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../student/student_home.dart';
import '../teacher/teacher_home.dart';
import '../admin/admin_dashboard.dart';
import '../auth/login_screen.dart';

class RoleBasedHome extends StatelessWidget {
  const RoleBasedHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);

    if (user.role == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    switch (user.role) {
      case 'student':
        return StudentHome();
      case 'teacher':
        return const TeacherHome();
      case 'admin':
        return const AdminDashboard();
      default:
        return const LoginScreen();
    }
  }
}
