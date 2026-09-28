import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../widgets/app_search_field.dart';

class AdminDataPage extends StatefulWidget {
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
  State<AdminDataPage> createState() => _AdminDataPageState();
}

class _AdminDataPageState extends State<AdminDataPage> {
  late Future<Map<String, dynamic>> _dataFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _dataFuture = ApiClient().get(widget.endpoint);
  }

  @override
  void didUpdateWidget(covariant AdminDataPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _query = '';
      _dataFuture = ApiClient().get(widget.endpoint);
    }
  }

  /// Tải bảng dữ liệu thật theo endpoint được chọn.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);
    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture,
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
        final keys = columnKeys;
        final query = _query.trim().toLowerCase();
        final filteredItems = items.where((item) {
          return query.isEmpty ||
              keys.any(
                (key) =>
                    item[key]?.toString().toLowerCase().contains(query) ??
                    false,
              );
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.title, style: AppTextStyles.displayLg(c.foreground)),
            const SizedBox(height: 16),
            AppSearchField(
              key: ValueKey(widget.endpoint),
              colors: c,
              hintText: 'Tìm trong ${widget.title.toLowerCase()}...',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 16),
            if (filteredItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    items.isEmpty
                        ? 'Chưa có dữ liệu.'
                        : 'Không tìm thấy kết quả phù hợp.',
                    style: AppTextStyles.bodySm(c.mutedForeground),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: widget.columns
                        .map((column) => DataColumn(label: Text(column)))
                        .toList(),
                    rows: filteredItems.map((item) {
                      return DataRow(
                        cells: widget.columns.map((column) {
                          final key = keys[widget.columns.indexOf(column)];
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

  /// Ánh xạ các cột hiển thị về key JSON từ từng endpoint.
  List<String> get columnKeys {
    if (widget.endpoint.endsWith('/units')) {
      return const ['id', 'name'];
    }
    if (widget.endpoint.endsWith('/users')) {
      return const ['id', 'name', 'email', 'role', 'status'];
    }
    if (widget.endpoint.endsWith('/classes')) {
      return const ['id', 'name', 'lecturerName', 'semester', 'studentCount'];
    }
    return const ['id', 'name', 'location', 'startTime', 'registeredCount'];
  }
}
