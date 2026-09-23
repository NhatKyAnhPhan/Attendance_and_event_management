// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.



import 'package:attendance_and_event_management/app.dart';
import 'package:attendance_and_event_management/controllers/auth_controller.dart';
import 'package:attendance_and_event_management/controllers/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts at the login page when no session exists', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    Get.put(ThemeController());
    Get.put(AuthController());

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập').first, findsOneWidget);
    Get.reset();
  });
}
