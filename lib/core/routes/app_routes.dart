/// Tên các route trong app — dùng chung cho AppPages và mọi lệnh Get.toNamed(...)
abstract class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const studentHome = '/student';
  static const adminShell = '/admin'; // dùng chung cho admin/lecturer/organizer
}