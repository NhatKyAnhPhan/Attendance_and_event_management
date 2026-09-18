import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppColors.radius),
      ),
      child: child,
    );
  }
}