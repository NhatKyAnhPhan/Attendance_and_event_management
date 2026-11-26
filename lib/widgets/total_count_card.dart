import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

class TotalCountCard extends StatelessWidget {
  final String label;
  final int count;

  const TotalCountCard({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(Theme.of(context).brightness == Brightness.dark);
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, color: colors.primary, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyXs(colors.mutedForeground)),
              const SizedBox(height: 3),
              Text('$count', style: AppTextStyles.displaySm(colors.foreground)),
            ],
          ),
        ],
      ),
    );
  }
}
