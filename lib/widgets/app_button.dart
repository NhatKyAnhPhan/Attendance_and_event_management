import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

enum AppButtonVariant { primary, secondary, outline, danger }
enum AppButtonSize { sm, md, lg }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final (bg, fg, border) = switch (variant) {
      AppButtonVariant.primary => (c.primary, c.primaryForeground, null),
      AppButtonVariant.secondary => (c.secondary, c.primary, null),
      AppButtonVariant.outline => (Colors.transparent, c.foreground, c.border),
      AppButtonVariant.danger => (c.danger, c.dangerForeground, null),
    };

    final (padding, fontSize) = switch (size) {
      AppButtonSize.sm => (const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 13.0),
      AppButtonSize.md => (const EdgeInsets.symmetric(horizontal: 18, vertical: 9), 14.0),
      AppButtonSize.lg => (const EdgeInsets.symmetric(horizontal: 24, vertical: 12), 15.0),
    };

    final child = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 2, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: AppTextStyles.button(fg).copyWith(fontSize: fontSize)),
            ],
          );

    final button = Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: loading ? null : onPressed,
        child: Container(
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: child,
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}