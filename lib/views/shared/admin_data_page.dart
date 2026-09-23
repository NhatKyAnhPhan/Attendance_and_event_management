import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';

class AdminDataPage extends StatelessWidget {
  final String title;
  final String endpoint;
  final List<String> columns;

  const AdminDataPage({
    super.key,
    required this.title,
    required this.endpoint,
    required this.columns,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiClient().get(endpoint),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final rawItems = snapshot.data?['items'];
        final items = rawItems is List
            ? rawItems.whereType<Map>().toList()
            : <Map>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(title, style: AppTextStyles.displayLg(c.foreground)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: c.card,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: columns
                      .map((column) => DataColumn(label: Text(column)))
                      .toList(),
                  rows: items.map((item) {
                    return DataRow(
                      cells: columns.map((column) {
                        final key = columnKeys[columns.indexOf(column)];
                        return DataCell(Text(item[key]?.toString() ?? ''));
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> get columnKeys {
    if (endpoint.endsWith('/users'))
      return const ['id', 'name', 'email', 'role', 'status'];
    if (endpoint.endsWith('/classes'))
      return const ['id', 'name', 'lecturerName', 'semester', 'studentCount'];
    return const ['id', 'name', 'location', 'startTime', 'registeredCount'];
  }
}
