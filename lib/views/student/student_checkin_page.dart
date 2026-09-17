import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Mục 14 bản thiết kế — "Student Mobile: QR Scanner, Processing state,
/// Success, Expired QR, Invalid QR, Already checked in".
/// Hiện tại chỉ implement scanning → success (giống UI gốc StudentMobilePage.tsx
/// thực tế render); các trạng thái expired/invalid/already sẽ thêm khi nối
/// mobile_scanner + API thật.
class StudentCheckinPage extends StatefulWidget {
  const StudentCheckinPage({super.key});

  @override
  State<StudentCheckinPage> createState() => _StudentCheckinPageState();
}

enum _ScanState { idle, scanning, success }

class _StudentCheckinPageState extends State<StudentCheckinPage> with SingleTickerProviderStateMixin {
  _ScanState _state = _ScanState.idle;
  late final AnimationController _lineCtrl;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _state = _ScanState.scanning);
    // TODO: thay bằng kết quả thật của mobile_scanner khi tích hợp camera.
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _state = _ScanState.success);
    });
  }

  void _reset() => setState(() => _state = _ScanState.idle);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Điểm danh QR',
                  style: TextStyle(color: Colors.white, fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Expanded(
              child: switch (_state) {
                _ScanState.idle => _buildIdle(c),
                _ScanState.scanning => _buildScanning(),
                _ScanState.success => _buildSuccess(c),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            'Nhấn nút bên dưới để bắt đầu quét mã QR điểm danh',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(onPressed: _startScan, child: const Text('Bắt đầu quét')),
          ),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                _corner(top: 0, left: 0),
                _corner(top: 0, right: 0),
                _corner(bottom: 0, left: 0),
                _corner(bottom: 0, right: 0),
                AnimatedBuilder(
                  animation: _lineCtrl,
                  builder: (context, child) => Positioned(
                    left: 4,
                    right: 4,
                    top: 8 + _lineCtrl.value * 224,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.transparent, Color(0xFF16A34A), Colors.transparent]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Đặt mã QR vào trong khung để điểm danh',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _corner({double? top, double? bottom, double? left, double? right}) {
    final isTop = top != null;
    final isLeft = left != null;
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: Color(0xFF16A34A), width: 3) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: Color(0xFF16A34A), width: 3) : BorderSide.none,
            left: isLeft ? const BorderSide(color: Color(0xFF16A34A), width: 3) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: Color(0xFF16A34A), width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(AppColors c) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Color(0xFF16A34A), size: 40),
          ),
          const SizedBox(height: 24),
          const Text('Điểm danh thành công!',
              style: TextStyle(color: Colors.white, fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 24)),
          const SizedBox(height: 8),
          // TODO: thay bằng tên lớp/sự kiện thật trả về từ API sau khi quét.
          Text('CS101 — Lập trình cơ bản', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} — ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(onPressed: _reset, child: const Text('Quét lại')),
          ),
        ],
      ),
    );
  }
}