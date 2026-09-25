import 'package:flutter/material.dart';

import '../../data/repositories/notification_repository.dart';
import '../../services/notification_service.dart';

class LecturerNotificationsPage extends StatefulWidget {
  const LecturerNotificationsPage({super.key});

  @override
  State<LecturerNotificationsPage> createState() =>
      _LecturerNotificationsPageState();
}

class _LecturerNotificationsPageState extends State<LecturerNotificationsPage> {
  bool _onlyUnread = false;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  late final NotificationService _service;

  @override
  void initState() {
    super.initState();
    _service = NotificationService(MockNotificationRepository());
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await _service.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = data;
        _isLoading = false;
      });
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'attendance':
        return Icons.fact_check_outlined;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'success':
        return Icons.check_circle_outline;
      default:
        return Icons.calendar_month_outlined;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'attendance':
        return const Color(0xFF1F5EA8);
      case 'warning':
        return const Color(0xFFD97706);
      case 'success':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF7C3AED);
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    if (!_onlyUnread) return _notifications;

    return _notifications.where((item) => item['read'] == false).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile),
              const SizedBox(height: 20),

              _buildToolbar(isDark, isMobile),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(50),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_visibleItems.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(50),
                    child: Text('Không có thông báo chưa đọc.'),
                  ),
                )
              else
                ..._visibleItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildNotificationCard(item, isDark),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thông báo',
          style: TextStyle(
            fontSize: isMobile ? 24 : 27,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Theo dõi các hoạt động và cập nhật mới nhất',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool isDark, bool isMobile) {
    final unread = _notifications.where((e) => e['read'] == false).length;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2A3D) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$unread thông báo chưa đọc',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _buildToolbarActions(),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    '$unread thông báo chưa đọc',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _buildToolbarActions(),
              ],
            ),
    );
  }

  Widget _buildToolbarActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: _onlyUnread,
          label: const Text('Chưa đọc'),
          onSelected: (value) {
            setState(() {
              _onlyUnread = value;
            });
          },
        ),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              for (final item in _notifications) {
                item['read'] = true;
              }
            });
          },
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Đánh dấu đã đọc'),
        ),
      ],
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item, bool isDark) {
    final read = item['read'] as bool;
    final color = _color(item['type']);

    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () {
        setState(() {
          item['read'] = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: !read
              ? isDark
                    ? const Color(0xFF25364E)
                    : const Color(0xFFF0F7FF)
              : isDark
              ? const Color(0xFF1E2A3D)
              : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: !read
                ? const Color(0xFFBFDBFE)
                : isDark
                ? const Color(0xFF334155)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_icon(item['type']), color: color),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['title'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: read
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                      ),

                      if (!read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    item['content'],
                    style: const TextStyle(color: Colors.grey, height: 1.4),
                  ),

                  const SizedBox(height: 9),

                  Text(
                    item['time'],
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
