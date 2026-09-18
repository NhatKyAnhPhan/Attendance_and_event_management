import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Bảng dữ liệu dùng chung — mỗi ô nhận Widget thay vì String để có thể nhét
/// AppBadge, AppButton... y hệt cách <td> trong ReportsPage.tsx/UsersPage.tsx.
class AppDataTable extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;

  const AppDataTable({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: c.border),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: c.muted),
            children: columns
                .map((col) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        col.toUpperCase(),
                        style: AppTextStyles.label(c.mutedForeground),
                      ),
                    ))
                .toList(),
          ),
          ...rows.map(
            (row) => TableRow(
              children: row
                  .map((cell) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: cell,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}