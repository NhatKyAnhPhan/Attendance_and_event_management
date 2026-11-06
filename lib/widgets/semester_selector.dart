import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class SemesterSelector extends StatelessWidget {
  const SemesterSelector({
    super.key,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final String value;
  final AppColors colors;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Học kỳ',
        isDense: true,
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'HK1', child: Text('Học kỳ 1')),
            DropdownMenuItem(value: 'HK2', child: Text('Học kỳ 2')),
            DropdownMenuItem(value: 'HK3', child: Text('Học kỳ 3')),
          ],
          onChanged: (semester) {
            if (semester != null) onChanged(semester);
          },
        ),
      ),
    );
  }
}
