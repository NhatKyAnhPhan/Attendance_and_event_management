import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Tương ứng class CSS `.badge` + `.badge-present/late/absent/pending/excused/blue`
class AppBadge extends StatelessWidget {
  final String label;
  final BadgeStatus status;
  const AppBadge({super.key, required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = badgeColors(status, isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyXs(colors[1]).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}