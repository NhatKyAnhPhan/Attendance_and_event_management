import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

class AppInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const AppInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    final field = TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: AppTextStyles.bodyMd(c.foreground),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: c.mutedForeground) : null,
        suffixIcon: suffixIcon,
      ),
    );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label!, style: AppTextStyles.bodySm(c.foreground).copyWith(fontWeight: FontWeight.w600)),
        ),
        field,
      ],
    );
  }
}