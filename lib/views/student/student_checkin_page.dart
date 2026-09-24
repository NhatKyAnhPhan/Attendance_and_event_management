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

enum _ScanState { idle, scanning, success, failed }
enum _ScanMethod { qr, face }

class _StudentCheckinPageState extends State<StudentCheckinPage>
    with SingleTickerProviderStateMixin {
  _ScanState _state = _ScanState.idle;
  _ScanMethod _method = _ScanMethod.qr;
  late final AnimationController _lineCtrl;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _state = _ScanState.scanning);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      final success = _method == _ScanMethod.face
          ? true
          : true; // có thể thay bằng logic thật sau này
      setState(() => _state = success ? _ScanState.success : _ScanState.failed);
    });
  }

  void _reset() => setState(() => _state = _ScanState.idle);

  void _setMethod(_ScanMethod method) {
    setState(() {
      _method = method;
      _state = _ScanState.idle;
    });
  }

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
              child: Text(
                _method == _ScanMethod.qr ? 'Điểm danh QR' : 'Nhận diện khuôn mặt',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            if (_state == _ScanState.idle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildMethodSelector(),
              ),
            Expanded(
              child: switch (_state) {
                _ScanState.idle => _buildIdle(c),
                _ScanState.scanning => _method == _ScanMethod.qr
                    ? _buildScanningQr()
                    : _buildScanningFace(),
                _ScanState.success => _buildSuccess(c),
                _ScanState.failed => _buildFailed(c),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MethodButton(
              label: 'QR',
              icon: Icons.qr_code_scanner,
              active: _method == _ScanMethod.qr,
              onTap: () => _setMethod(_ScanMethod.qr),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MethodButton(
              label: 'Face',
              icon: Icons.face_retouching_natural,
              active: _method == _ScanMethod.face,
              onTap: () => _setMethod(_ScanMethod.face),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(AppColors c) {
    final title = _method == _ScanMethod.qr
        ? 'Nhấn nút bên dưới để bắt đầu quét mã QR điểm danh'
        : 'Nhấn nút bên dưới để bắt đầu nhận diện khuôn mặt';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _method == _ScanMethod.qr
                  ? Icons.qr_code_scanner
                  : Icons.face_retouching_natural,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _startScan,
              child: Text(
                _method == _ScanMethod.qr ? 'Bắt đầu quét QR' : 'Bắt đầu nhận diện',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningQr() {
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
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 2,
                    ),
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
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFF16A34A),
                            Colors.transparent,
                          ],
                        ),
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
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningFace() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                Center(
                  child: Container(
                    width: 160,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF60A5FA),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(80),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Icon(
                          Icons.face_6_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 82,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _lineCtrl,
                  builder: (context, child) => Positioned(
                    left: 18,
                    right: 18,
                    top: 20 + _lineCtrl.value * 200,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFF60A5FA),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Vui lòng nhìn thẳng vào camera để hệ thống nhận diện',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
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
            top: isTop
                ? const BorderSide(color: Color(0xFF16A34A), width: 3)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: Color(0xFF16A34A), width: 3)
                : BorderSide.none,
            left: isLeft
                ? const BorderSide(color: Color(0xFF16A34A), width: 3)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: Color(0xFF16A34A), width: 3)
                : BorderSide.none,
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
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Color(0xFF16A34A), size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Điểm danh thành công!',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _method == _ScanMethod.qr
                ? 'CS101 — Lập trình cơ bản'
                : 'Nhận diện khuôn mặt thành công — CS101',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} — ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _reset,
              child: const Text('Quét lại'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Color(0xFFDC2626), size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Không thể xác thực',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _method == _ScanMethod.qr
                ? 'Mã QR không hợp lệ hoặc đã hết hạn.'
                : 'Khuôn mặt chưa rõ nét, vui lòng thử lại.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Thử lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _setMethod(_method),
                  child: const Text('Làm mới'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _MethodButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? const Color(0xFF1E56A0) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF1E56A0) : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}