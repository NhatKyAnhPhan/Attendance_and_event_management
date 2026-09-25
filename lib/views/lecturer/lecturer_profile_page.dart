import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/auth_controller.dart';
import '../../data/models/lecturer_profile_model.dart';
import '../../data/repositories/lecturer_profile_repository.dart';
import '../../services/lecturer_profile_service.dart';

class LecturerProfilePage extends StatefulWidget {
  final VoidCallback? onBack;
  const LecturerProfilePage({super.key, this.onBack});

  @override
  State<LecturerProfilePage> createState() => _LecturerProfilePageState();
}

class _LecturerProfilePageState extends State<LecturerProfilePage> {
  final LecturerProfileService _service = LecturerProfileService(MockLecturerProfileRepository());
  final AuthController _authController = Get.find<AuthController>();
  
  bool _isLoading = true;
  LecturerProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _authController.currentUser.value;
    if (user != null) {
      final identifier = user.email.isNotEmpty == true ? user.email : (user.code);
      final profile = await _service.getProfile(identifier);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profile == null) {
      return const Center(child: Text('Không tìm thấy thông tin giảng viên.'));
    }

    final p = _profile!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E2A3D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final mutedColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.onBack != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onBack,
                    ),
                  Text(
                    'Hồ sơ của tôi',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Chức năng chỉnh sửa sẽ được bổ sung sau.')),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Chỉnh sửa thông tin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F5EA8),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 768;
                  final leftCol = _buildLeftCol(p, cardColor, textColor, mutedColor);
                  final rightCol = _buildRightCol(p, cardColor, textColor, mutedColor);

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 320, child: leftCol),
                        const SizedBox(width: 24),
                        Expanded(child: rightCol),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        leftCol,
                        const SizedBox(height: 24),
                        rightCol,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftCol(LecturerProfileModel p, Color cardColor, Color textColor, Color mutedColor) {
    final initial = p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : 'G';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFF1F5EA8),
            child: Text(
              initial,
              style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            p.fullName,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            p.position,
            style: TextStyle(color: mutedColor, fontSize: 14),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.email_outlined, 'Email', p.email, textColor, mutedColor),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.phone_outlined, 'Điện thoại', p.phone, textColor, mutedColor),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.badge_outlined, 'Mã GV', p.code, textColor, mutedColor),
        ],
      ),
    );
  }

  Widget _buildRightCol(LecturerProfileModel p, Color cardColor, Color textColor, Color mutedColor) {
    return Column(
      children: [
        _buildSection(
          'Thông tin cơ bản',
          Icons.person_outline,
          [
            _buildGridItem('Họ và tên', p.fullName, textColor, mutedColor),
            _buildGridItem('Mã giảng viên', p.code, textColor, mutedColor),
            _buildGridItem('Giới tính', p.gender, textColor, mutedColor),
            _buildGridItem('Ngày sinh', p.dateOfBirth, textColor, mutedColor),
            _buildGridItem('Quê quán', p.hometown, textColor, mutedColor),
            _buildGridItem('Địa chỉ hiện tại', p.currentAddress, textColor, mutedColor),
          ],
          cardColor,
          textColor,
        ),
        const SizedBox(height: 24),
        _buildSection(
          'Thông tin công tác',
          Icons.work_outline,
          [
            _buildGridItem('Đơn vị công tác', p.organization, textColor, mutedColor),
            _buildGridItem('Khoa', p.faculty, textColor, mutedColor),
            _buildGridItem('Bộ môn', p.department, textColor, mutedColor),
            _buildGridItem('Chức vụ', p.position, textColor, mutedColor),
            _buildGridItem('Ngày bắt đầu', p.startDate, textColor, mutedColor),
            _buildGridItem('Trạng thái', p.employmentStatus, textColor, mutedColor),
          ],
          cardColor,
          textColor,
        ),
        const SizedBox(height: 24),
        _buildSection(
          'Học vấn',
          Icons.school_outlined,
          [
            _buildGridItem('Học vị', p.academicDegree, textColor, mutedColor),
            _buildGridItem('Chuyên ngành', p.major, textColor, mutedColor),
            _buildGridItem('Trường tốt nghiệp', p.university, textColor, mutedColor),
            _buildGridItem('Năm tốt nghiệp', p.graduationYear, textColor, mutedColor),
          ],
          cardColor,
          textColor,
        ),
        const SizedBox(height: 24),
        _buildSection(
          'Thông tin tài khoản',
          Icons.admin_panel_settings_outlined,
          [
            _buildGridItem('Tên đăng nhập', p.code, textColor, mutedColor),
            _buildGridItem('Email', p.email, textColor, mutedColor),
            _buildGridItem('Vai trò', 'Giảng viên', textColor, mutedColor),
            _buildGridItem('Trạng thái tài khoản', p.accountStatus, textColor, mutedColor),
          ],
          cardColor,
          textColor,
        ),
      ],
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1F5EA8), size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.5,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: children,
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(String label, String value, Color textColor, Color mutedColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: mutedColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color textColor, Color mutedColor) {
    return Row(
      children: [
        Icon(icon, size: 20, color: mutedColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: mutedColor, fontSize: 12)),
              Text(value, style: TextStyle(color: textColor, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
