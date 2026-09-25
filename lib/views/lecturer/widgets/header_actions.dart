import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../controllers/auth_controller.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../services/notification_service.dart';

class LecturerNotificationAction extends StatefulWidget {
  final VoidCallback onTap;

  const LecturerNotificationAction({super.key, required this.onTap});

  @override
  State<LecturerNotificationAction> createState() => _LecturerNotificationActionState();
}

class _LecturerNotificationActionState extends State<LecturerNotificationAction> {
  final NotificationService _service = NotificationService(MockNotificationRepository());
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => n['read'] == false).length;

    return IconButton(
      tooltip: 'Thông báo',
      onPressed: widget.onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_outlined),
          if (unread > 0)
            Positioned(
              top: -1,
              right: -1,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LecturerNotificationPanel extends StatefulWidget {
  final VoidCallback onSeeAll;

  const LecturerNotificationPanel({super.key, required this.onSeeAll});

  @override
  State<LecturerNotificationPanel> createState() => _LecturerNotificationPanelState();
}

class _LecturerNotificationPanelState extends State<LecturerNotificationPanel> {
  final NotificationService _service = NotificationService(MockNotificationRepository());
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 380,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Thông báo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _notifications.take(5).length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        title: Text(n['title'], style: TextStyle(fontWeight: n['read'] == false ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(n['content'] ?? '', style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(n['time'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () {},
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSeeAll();
              },
              child: const Text('Xem tất cả thông báo'),
            ),
          ),
        ],
      ),
    );
  }
}

class LecturerAvatarAction extends StatelessWidget {
  final VoidCallback onTap;
  const LecturerAvatarAction({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() {
      final user = auth.currentUser.value;
      final name = user?.name?.isNotEmpty == true ? user!.name : 'Giảng viên';
      final initial = name.isNotEmpty ? name.split(' ').last[0].toUpperCase() : 'G';

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF1F5EA8),
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    });
  }
}

class LecturerProfilePanel extends StatelessWidget {
  final VoidCallback onViewProfile;
  const LecturerProfilePanel({super.key, required this.onViewProfile});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final user = auth.currentUser.value;
    
    final name = (user?.name?.isNotEmpty == true) ? user!.name : (user?.code ?? 'Giảng viên');
    final initial = name.isNotEmpty ? name.split(' ').last[0].toUpperCase() : 'G';
    final email = user?.email ?? 'Không có email';
    final dept = user?.department ?? 'Không rõ';
    final code = user?.code ?? '';

    return Drawer(
      width: 320,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Thông tin giảng viên', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF1F5EA8),
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 16),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(email, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Vai trò'),
            subtitle: const Text('Giảng viên'),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Mã giảng viên'),
            subtitle: Text(code.isEmpty ? 'Không rõ' : code),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Khoa / Bộ môn'),
            subtitle: Text(dept),
          ),
          
          const Spacer(),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onViewProfile();
                    },
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Thông tin cá nhân'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      auth.logout();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Đăng xuất'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
