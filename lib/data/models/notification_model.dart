import 'package:flutter/material.dart';

import '../../core/constants/role.dart';

enum NotificationType { attendance, classUpdate, event, certificate, system, approval }

enum NotificationPriority { low, normal, high }

class AppNotificationItem {
  final String id;
  final List<Role> recipients;
  final String title;
  final String message;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime createdAt;
  final bool read;
  final String? actionLabel;
  final String? route;

  const AppNotificationItem({
    required this.id,
    required this.recipients,
    required this.title,
    required this.message,
    required this.type,
    this.priority = NotificationPriority.normal,
    required this.createdAt,
    this.read = false,
    this.actionLabel,
    this.route,
  });

  AppNotificationItem copyWith({
    String? id,
    List<Role>? recipients,
    String? title,
    String? message,
    NotificationType? type,
    NotificationPriority? priority,
    DateTime? createdAt,
    bool? read,
    String? actionLabel,
    String? route,
  }) {
    return AppNotificationItem(
      id: id ?? this.id,
      recipients: recipients ?? this.recipients,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
      actionLabel: actionLabel ?? this.actionLabel,
      route: route ?? this.route,
    );
  }

  String get timeLabel {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }

  IconData get icon {
    switch (type) {
      case NotificationType.attendance:
        return Icons.check_circle_outline;
      case NotificationType.classUpdate:
        return Icons.school_outlined;
      case NotificationType.event:
        return Icons.event_available_outlined;
      case NotificationType.certificate:
        return Icons.workspace_premium_outlined;
      case NotificationType.system:
        return Icons.info_outline;
      case NotificationType.approval:
        return Icons.fact_check_outlined;
    }
  }
}
