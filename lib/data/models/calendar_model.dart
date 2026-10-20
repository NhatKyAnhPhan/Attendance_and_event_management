class CalendarClass {
  final String id;
  final String name;
  final String subjectName;
  final String lecturerName;
  final List<CalendarClassSchedule> schedules;

  const CalendarClass({
    required this.id,
    required this.name,
    required this.subjectName,
    required this.lecturerName,
    required this.schedules,
  });

  factory CalendarClass.fromJson(Map<String, dynamic> json) {
    final schedules = json['schedules'];
    return CalendarClass(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      subjectName: json['subjectName']?.toString() ?? '',
      lecturerName: json['lecturerName']?.toString() ?? '',
      schedules: schedules is List
          ? schedules
                .whereType<Map>()
                .map(
                  (item) => CalendarClassSchedule.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class CalendarClassSchedule {
  final int weekday;
  final String startTime;
  final String endTime;
  final String room;
  final DateTime? startsOn;
  final DateTime? endsOn;

  const CalendarClassSchedule({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.startsOn,
    required this.endsOn,
  });

  factory CalendarClassSchedule.fromJson(Map<String, dynamic> json) =>
      CalendarClassSchedule(
        weekday: int.tryParse(json['weekday']?.toString() ?? '') ?? 0,
        startTime: json['startTime']?.toString() ?? '',
        endTime: json['endTime']?.toString() ?? '',
        room: json['room']?.toString() ?? '',
        startsOn: DateTime.tryParse(json['startsOn']?.toString() ?? ''),
        endsOn: DateTime.tryParse(json['endsOn']?.toString() ?? ''),
      );
}
