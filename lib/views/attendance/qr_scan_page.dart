import 'package:flutter/material.dart';

import '../student/student_checkin_page.dart';

class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key});

  // Dùng luồng quét mã và ghi nhận điểm danh của sinh viên.
  @override
  Widget build(BuildContext context) {
    return const StudentCheckinPage();
  }
}
