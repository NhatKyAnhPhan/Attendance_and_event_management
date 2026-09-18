import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

class AppTabBar extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const AppTabBar({super.key, required this.tabs, required this.activeIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == activeIndex;
          return InkWell(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: active ? c.primary : Colors.transparent, width: 2)),
              ),
              child: Text(
                tabs[i],
                style: AppTextStyles.bodyMd(active ? c.primary : c.mutedForeground)
                    .copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500),
              ),
            ),
          );
        }),
      ),
    );
  }
}