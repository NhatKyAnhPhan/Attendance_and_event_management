enum EventRegistrationStatus { notRegistered, pending, approved, rejected }

class OrganizerUnit {
  final String id;
  final String name;

  const OrganizerUnit({required this.id, required this.name});

  factory OrganizerUnit.fromJson(Map<String, dynamic> json) {
    return OrganizerUnit(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

/// Góp ý giảng viên: sự kiện cần thời gian/địa điểm rõ ràng + yêu cầu
/// "Đăng ký" (khác với lớp học chỉ cần "Join").
class EventModel {
  final String id;
  final String name;
  final String organizerId;
  final String organizerName;
  final DateTime startTime;
  final DateTime endTime;
  final String location;
  final int capacity;
  final int registeredCount;
  final bool requiresApproval;

  const EventModel({
    required this.id,
    required this.name,
    required this.organizerId,
    required this.organizerName,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.capacity,
    required this.registeredCount,
    this.requiresApproval = true,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      name: json['name'] as String,
      organizerId: json['organizerId'] as String? ?? '',
      organizerName: json['organizerName'] as String? ?? '',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      location: json['location'] as String? ?? '',
      capacity: json['capacity'] as int? ?? 0,
      registeredCount: json['registeredCount'] as int? ?? 0,
      requiresApproval: json['requiresApproval'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'organizerId': organizerId,
    'organizerName': organizerName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'location': location,
    'capacity': capacity,
    'registeredCount': registeredCount,
    'requiresApproval': requiresApproval,
  };
}

class OrganizerEventSummary {
  final String id;
  final String name;
  final String organizerId;
  final String location;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final int capacity;
  final int registeredCount;

  const OrganizerEventSummary({
    required this.id,
    required this.name,
    required this.organizerId,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.capacity,
    required this.registeredCount,
  });

  factory OrganizerEventSummary.fromJson(Map<String, dynamic> json) {
    return OrganizerEventSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      organizerId: json['organizerId']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      startTime: DateTime.parse(json['startTime'].toString()),
      endTime: DateTime.parse(
        json['endTime']?.toString() ?? json['startTime'].toString(),
      ),
      status: json['status']?.toString() ?? 'Sắp diễn ra',
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      registeredCount: (json['registeredCount'] as num?)?.toInt() ?? 0,
    );
  }
}
