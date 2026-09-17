import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Tương ứng `function PlaceholderPage({ title })` trong App.tsx —
/// dùng tạm cho route nào chưa code xong, sẽ thay dần bằng trang thật.
class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚧', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.displayMd(c.foreground)),
            const SizedBox(height: 8),
            Text(
              'Màn hình này đang được phát triển',
              style: AppTextStyles.bodySm(c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}