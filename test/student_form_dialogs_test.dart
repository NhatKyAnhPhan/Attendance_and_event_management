import 'package:attendance_and_event_management/controllers/admin_classes_controller.dart';
import 'package:attendance_and_event_management/controllers/auth_controller.dart';
import 'package:attendance_and_event_management/controllers/classes_controller.dart';
import 'package:attendance_and_event_management/controllers/events_controller.dart';
import 'package:attendance_and_event_management/controllers/organizer_events_controller.dart';
import 'package:attendance_and_event_management/core/constants/role.dart';
import 'package:attendance_and_event_management/data/models/class_model.dart';
import 'package:attendance_and_event_management/data/models/event_model.dart';
import 'package:attendance_and_event_management/data/models/student_roster_entry.dart';
import 'package:attendance_and_event_management/data/models/student_summaries.dart';
import 'package:attendance_and_event_management/views/classes/classes_page.dart';
import 'package:attendance_and_event_management/views/events/organizer_events_page.dart';
import 'package:attendance_and_event_management/views/student/student_classes_page.dart';
import 'package:attendance_and_event_management/views/student/student_events_page.dart';
import 'package:attendance_and_event_management/widgets/student_form_dialogs.dart';
import 'package:attendance_and_event_management/widgets/student_roster_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TestAuthController extends AuthController {
  @override
  // Test double intentionally skips session restoration.
  // ignore: must_call_super
  void onInit() {}
}

class _TestEventsController extends EventsController {
  int commentSubmissions = 0;
  int refreshes = 0;
  int detailLoads = 0;
  int historyLoads = 0;

  @override
  // Test double intentionally skips API loading and the refresh timer.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> submitComment({
    required String eventId,
    required String comment,
  }) async {
    commentSubmissions++;
  }

  @override
  Future<void> load() async {
    refreshes++;
  }

  @override
  Future<Map<String, dynamic>> getDetails(String eventId) async {
    detailLoads++;
    return {
      'name': 'Sự kiện kiểm thử',
      'organizerName': 'HUIT',
      'description': 'Mô tả kiểm thử',
      'location': 'Hội trường',
      'startTime': '2026-10-20T08:00:00.000Z',
      'endTime': '2026-10-20T10:00:00.000Z',
      'capacity': 100,
      'registeredCount': 20,
      'benefits': <Map<String, dynamic>>[],
      'rules': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> getFeedback(String eventId) async {
    return {
      'averageRating': 4.5,
      'ratingCount': 2,
      'items': [
        {
          'rating': 5,
          'comment': 'Nội dung đánh giá kiểm thử khá dài để xác nhận giao diện tự xuống dòng trên màn hình hẹp.',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getMyFeedback() async {
    historyLoads++;
    return {
      'feedbackItems': [
        {
          'id': 'PH01',
          'targetType': 'event',
          'targetName': 'Ngày hội kiểm thử',
          'eventId': 'SK01',
          'classId': null,
          'content': 'Phản hồi đã gửi',
          'createdAt': '2026-10-15T08:30:00.000Z',
        },
      ],
      'ratingItems': [
        {
          'id': 'DG01',
          'targetType': 'class',
          'targetName': 'Lập trình ứng dụng',
          'eventId': null,
          'classId': 'LHP001',
          'rating': 4,
          'content': 'Đánh giá đã gửi',
          'createdAt': '2026-10-14T08:30:00.000Z',
        },
      ],
    };
  }
}

class _TestClassesController extends ClassesController {
  int commentSubmissions = 0;
  int refreshes = 0;

  @override
  // Test double intentionally skips API loading and the refresh timer.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> submitComment({
    required String classId,
    required String comment,
  }) async {
    commentSubmissions++;
  }

  @override
  Future<void> load() async {
    refreshes++;
  }
}

class _TestAdminClassesController extends AdminClassesController {
  @override
  // Test double intentionally skips API loading and the refresh timer.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {}

  @override
  Future<void> loadLecturers() async {}

  @override
  Future<void> loadClassOptions() async {}
}

class _TestOrganizerEventsController extends OrganizerEventsController {
  @override
  // Test double intentionally skips API loading and the refresh timer.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {}

  @override
  Future<void> loadUnits() async {}

  @override
  Future<Map<String, dynamic>> getEventDetails(String eventId) async {
    return {
      'organizerName': 'Đơn vị tổ chức có tên rất dài để kiểm tra responsive',
      'description': 'Mô tả sự kiện dài, giữ nguyên dữ liệu và cho phép modal cuộn tự nhiên trên màn hình hẹp.',
      'registeredCount': 1,
      'capacity': 100,
      'benefits': <Map<String, dynamic>>[],
      'rules': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<StudentRosterEntry>> getEventStudents(String eventId) async {
    return const [
      StudentRosterEntry(
        studentId: '200123000700000000000000',
        studentName:
            'Sinh viên có họ và tên rất dài trong danh sách đăng ký sự kiện',
        email: 'email.rat.dai.cua.sinh.vien@huit.edu.vn',
        status: 'Đã đăng ký và đang hoạt động',
        attendanceStatus: 'Đã điểm danh QR',
        dateLabel: 'Tham gia ngày 15/10/2026 lúc 08:30',
      ),
    ];
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    final auth = Get.put<AuthController>(_TestAuthController());
    auth.currentUser.value = {'id': 'SV001', 'role': 'student'};
  });

  tearDown(Get.reset);

  testWidgets('submits event feedback, refreshes, and closes once', (
    tester,
  ) async {
    final events = _TestEventsController();
    final classes = _TestClassesController();
    events.items.add(
      StudentEventSummary(
        id: 'SK01',
        name: 'Sự kiện kiểm thử',
        date: '',
        org: 'HUIT',
        registered: true,
        endTime: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );

    await _pumpFeedbackHost(
      tester,
      events: events,
      classes: classes,
      target: StudentFeedbackTarget.event,
      itemId: 'SK01',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Phản hồi sự kiện');
    await tester.tap(find.text('Gửi phản hồi').last);
    await tester.pumpAndSettle();

    expect(events.commentSubmissions, 1);
    expect(events.refreshes, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Đã gửi phản hồi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('class feedback dropdown uses two lines without overflow', (
    tester,
  ) async {
    final events = _TestEventsController();
    final classes = _TestClassesController();
    classes.items.add(
      const StudentClassSummary(
        id: 'LHP001',
        name: 'Lập trình ứng dụng',
        lecturer: 'Nguyễn Văn A',
        time: '',
        room: '',
        present: 0,
        late: 0,
        absent: 0,
        sessions: 0,
        rate: 0,
      ),
    );

    await _pumpFeedbackHost(
      tester,
      events: events,
      classes: classes,
      target: StudentFeedbackTarget.classSection,
      itemId: 'LHP001',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Lập trình ứng dụng'), findsWidgets);
    expect(find.text('LHP001 · Nguyễn Văn A'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Lập trình ứng dụng').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Phản hồi lớp học');
    await tester.tap(find.text('Gửi phản hồi').last);
    await tester.pumpAndSettle();

    expect(classes.commentSubmissions, 1);
    expect(classes.refreshes, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the signed-in student feedback history', (tester) async {
    final events = _TestEventsController();
    final classes = _TestClassesController();

    await _pumpFeedbackHost(
      tester,
      events: events,
      classes: classes,
      target: StudentFeedbackTarget.event,
      itemId: null,
    );
    await tester.tap(find.text('Phản hồi đã gửi'));
    await tester.pumpAndSettle();

    expect(events.historyLoads, 1);
    expect(find.text('Ngày hội kiểm thử'), findsOneWidget);
    expect(find.text('Phản hồi đã gửi'), findsWidgets);
    expect(find.text('Sự kiện'), findsOneWidget);
    expect(find.text('Đóng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the signed-in student rating history', (tester) async {
    final events = _TestEventsController();
    final classes = _TestClassesController();

    await _pumpFeedbackHost(
      tester,
      events: events,
      classes: classes,
      target: StudentFeedbackTarget.classSection,
      itemId: null,
      rating: true,
    );
    await tester.tap(find.text('Đánh giá đã gửi'));
    await tester.pumpAndSettle();

    expect(events.historyLoads, 1);
    expect(find.text('Lập trình ứng dụng'), findsOneWidget);
    expect(find.text('Đánh giá đã gửi'), findsWidgets);
    expect(find.text('Lớp học phần'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('event registration uses two wizard steps with loaded details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = Get.find<AuthController>();
    auth.currentUser.value = {
      'id': 'SV001',
      'name': 'Sinh viên kiểm thử',
      'email': 'student@huit.edu.vn',
      'phone': '0900000000',
      'address': 'TP.HCM',
      'className': 'CNTT01',
      'major': 'Kỹ thuật phần mềm',
      'role': 'student',
    };
    final events = Get.put<EventsController>(_TestEventsController());
    final event = StudentEventSummary(
      id: 'SK01',
      name: 'Sự kiện kiểm thử',
      date: '',
      org: 'HUIT',
      location: 'Hội trường',
      registered: false,
      startTime: DateTime(2026, 10, 20, 15),
      endTime: DateTime(2026, 10, 20, 17),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showStudentRegistrationDialog(
                context: context,
                events: [event],
                initialEventId: event.id,
                onSubmit: (_) async => true,
              ),
              child: const Text('Mở đăng ký'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở đăng ký'));
    await tester.pumpAndSettle();

    expect(find.text('Bước 1/2 — Thông tin sự kiện'), findsOneWidget);
    expect(find.text('Mô tả kiểm thử'), findsOneWidget);
    expect((events as _TestEventsController).detailLoads, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.text('Bước 2/2 — Thông tin sinh viên'), findsOneWidget);
    expect(find.text('student@huit.edu.vn'), findsOneWidget);
    expect(find.text('CNTT01'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
    expect(find.text('Xác nhận đăng ký'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create class subject dropdown and footer fit a short window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = Get.find<AuthController>();
    auth.role.value = Role.admin;
    final controller = _TestAdminClassesController();
    controller.subjects.add(
      const ClassSubjectOption(
        id: 'MH01',
        code: 'MOB1014',
        name: 'Lập trình thiết bị di động nâng cao',
        majorId: 'BM01',
        majorName: 'Công nghệ phần mềm',
        departmentId: 'K01',
        semester: 'HK1',
        credits: 3,
      ),
    );
    controller.cohorts.add(const ClassCohort(code: 'K18'));
    Get.put<AdminClassesController>(controller);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ClassesPage())),
    );
    await tester.pump();
    await tester.tap(find.text('Tạo lớp'));
    await tester.pumpAndSettle();

    expect(find.text('Lưu'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Lưu')).dy, lessThan(500));

    await tester.tap(find.byType(DropdownButtonFormField<ClassSubjectOption>));
    await tester.pumpAndSettle();

    expect(find.text('Lập trình thiết bị di động nâng cao'), findsWidgets);
    expect(find.text('MOB1014 · 3 tín chỉ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student event details fit all requested responsive widths', (
    tester,
  ) async {
    final events = Get.put<EventsController>(_TestEventsController());
    Get.put<ClassesController>(_TestClassesController());
    events.items.add(
      StudentEventSummary(
        id: 'SK-RESPONSIVE-001',
        name: 'Sự kiện kiểm thử responsive với tên rất dài trên nhiều kích thước thiết bị',
        date: '20/10/2026 08:00',
        org: 'Trường Đại học Công Thương Thành phố Hồ Chí Minh',
        location: 'Hội trường lớn với tên địa điểm rất dài',
        registered: true,
        registeredAt: DateTime(2026, 10, 1, 8, 30),
        startTime: DateTime.now().subtract(const Duration(days: 2)),
        endTime: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    for (final width in const [360.0, 390.0, 427.0, 768.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(width),
          home: const Scaffold(body: StudentEventsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem chi tiết'));
      await tester.pumpAndSettle();

      expect(find.text('Đơn vị tổ chức'), findsOneWidget);
      expect(find.text('Quyền lợi'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Phản hồi và đánh giá'),
        280,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Phản hồi và đánh giá'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('student class cards fit all requested responsive widths', (
    tester,
  ) async {
    final classes = Get.put<ClassesController>(_TestClassesController());
    Get.put<EventsController>(_TestEventsController());
    classes.items.add(
      const StudentClassSummary(
        id: 'LHP-RESPONSIVE-001',
        name: 'Lập trình ứng dụng đa nền tảng với tên lớp học phần rất dài',
        lecturer: 'Giảng viên có họ và tên rất dài để kiểm tra responsive',
        time: 'Thứ hai, tiết 1 đến tiết 5 trong nhiều tuần',
        room: 'Phòng thực hành có tên rất dài',
        studentCount: 42,
        capacity: 50,
        credits: 3,
        present: 12,
        late: 2,
        absent: 1,
        sessions: 15,
        rate: 80,
      ),
    );

    for (final width in const [360.0, 390.0, 427.0, 768.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StudentClassesPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phản hồi'), findsOneWidget);
      expect(find.text('Đánh giá'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('student roster keeps long identity and statuses in bounds', (
    tester,
  ) async {
    const student = StudentRosterEntry(
      studentId: '200123000700000000000000',
      studentName: 'Sinh viên có họ và tên rất dài để kiểm tra việc xuống dòng',
      email: 'dia.chi.email.rat.dai.cua.sinh.vien@huit.edu.vn',
      status: 'Đang hoạt động với trạng thái dài',
      attendanceStatus: 'Đã điểm danh QR',
      dateLabel: 'Tham gia ngày 15/10/2026 lúc 08:30',
    );

    for (final width in const [360.0, 390.0, 427.0, 768.0]) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: StudentRosterList(
                students: const [student],
                mutedColor: Colors.grey,
                dividerColor: Colors.blueGrey,
                emptyMessage: 'Không có sinh viên.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(student.studentName), findsOneWidget);
      expect(find.text(student.email), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('staff event detail roster fits all requested widths', (
    tester,
  ) async {
    final auth = Get.find<AuthController>();
    auth.role.value = Role.organizer;
    auth.currentUser.value = {'id': 'NV001', 'role': 'Công nhân viên'};
    final controller = Get.put<OrganizerEventsController>(
      _TestOrganizerEventsController(),
    );
    final event = OrganizerEventSummary(
      id: 'SK-NV-001',
      name: 'Sự kiện dành cho tài khoản Công nhân viên với tên rất dài để kiểm tra',
      organizerId: 'DV001',
      location: 'Địa điểm tổ chức có tên rất dài',
      startTime: DateTime.now().add(const Duration(days: 1)),
      endTime: DateTime.now().add(const Duration(days: 2)),
      capacity: 100,
      registeredCount: 1,
    );
    controller.items.add(event);

    for (final width in const [360.0, 390.0, 427.0, 768.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('staff-$width'),
          home: const Scaffold(body: OrganizerEventsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(event.name).first);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Danh sách sinh viên đăng ký (1)'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Sinh viên có họ và tên rất dài trong danh sách đăng ký sự kiện',
        ),
        findsOneWidget,
      );
      expect(
        find.text('email.rat.dai.cua.sinh.vien@huit.edu.vn'),
        findsOneWidget,
      );
      expect(find.text('Đã điểm danh QR'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

Future<void> _pumpFeedbackHost(
  WidgetTester tester, {
  required EventsController events,
  required ClassesController classes,
  required StudentFeedbackTarget target,
  required String? itemId,
  bool rating = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => rating
                ? showStudentRatingDialog(
                    context: context,
                    eventsController: events,
                    classesController: classes,
                    initialTarget: target,
                    initialItemId: itemId,
                  )
                : showStudentFeedbackDialog(
                    context: context,
                    eventsController: events,
                    classesController: classes,
                    initialTarget: target,
                    initialItemId: itemId,
                  ),
            child: const Text('Mở phản hồi'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở phản hồi'));
  await tester.pumpAndSettle();
}
