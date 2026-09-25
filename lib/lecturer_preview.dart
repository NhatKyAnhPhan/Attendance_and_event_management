import 'package:flutter/material.dart';

import 'views/lecturer/lecturer_shell_page.dart';

void main() {
  runApp(const LecturerPreviewApp());
}

class LecturerPreviewApp extends StatelessWidget {
  const LecturerPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HUIT - Giảng viên',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F5EA8),
          brightness: Brightness.light,
        ),
        fontFamily: 'Arial',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111827),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Arial',
      ),
      home: const LecturerShellPage(),
    );
  }
}