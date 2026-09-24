import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border.all(color: c.border, width: 2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.primary, width: 2),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _Corner(isTop: true, isLeft: true, color: c.primary),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _Corner(isTop: true, isLeft: false, color: c.primary),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: _Corner(isTop: false, isLeft: true, color: c.primary),
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: _Corner(isTop: false, isLeft: false, color: c.primary),
                      ),
                      Center(
                        child: Icon(Icons.qr_code_scanner, size: 80, color: c.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Quét mã QR điểm danh', style: AppTextStyles.displayLg(c.foreground)),
                const SizedBox(height: 8),
                Text(
                  'Đặt mã vào vùng quét và hệ thống sẽ tự động xác nhận.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm(c.mutedForeground),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Bắt đầu quét'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final bool isTop;
  final bool isLeft;
  final Color color;

  const _Corner({required this.isTop, required this.isLeft, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
        ),
      ),
    );
  }
}
