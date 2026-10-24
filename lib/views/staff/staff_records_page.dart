import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/statistics_charts.dart';

/// Loại dữ liệu cán bộ có thể xem trong khu vực này.
enum StaffRecordKind { certificates, feedback }

/// Hiển thị chứng chỉ hoặc phản hồi được tải trực tiếp từ backend.
class StaffRecordsPage extends StatefulWidget {
  /// Tạo màn danh sách cho loại dữ liệu được chọn.
  const StaffRecordsPage({super.key, required this.kind});

  final StaffRecordKind kind;

  @override
  /// Tạo state quản lý tải dữ liệu và bộ lọc cục bộ.
  State<StaffRecordsPage> createState() => _StaffRecordsPageState();
}

class _StaffRecordsPageState extends State<StaffRecordsPage> {
  late Future<Map<String, dynamic>> _dataFuture;
  String _query = '';
  String _filter = 'all';

  bool _isCertificateIssued(Map<String, dynamic> item) =>
      item['status']?.toString().trim().toLowerCase() == 'đã cấp';

  String _certificateStatus(Map<String, dynamic> item) =>
      _isCertificateIssued(item) ? 'Đã cấp' : 'Chưa cấp';

  /// Tải bản ghi thật khi màn hình được khởi tạo.
  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  /// Lấy dữ liệu chứng chỉ hoặc phản hồi từ endpoint tương ứng.
  Future<Map<String, dynamic>> _loadData() {
    final endpoint = widget.kind == StaffRecordKind.certificates
        ? ApiEndpoints.staffCertificates
        : ApiEndpoints.staffFeedback;
    return ApiClient().get(endpoint);
  }

  /// Tải lại dữ liệu khi người dùng kéo để làm mới.
  Future<void> _refresh() async {
    final future = _loadData();
    setState(() => _dataFuture = future);
    await future.then<void>((_) {}, onError: (Object _) {});
  }

  /// Lọc bản ghi theo từ khóa và trạng thái hoặc loại phản hồi đang chọn.
  List<Map<String, dynamic>> _filteredItems(List<Map<String, dynamic>> items) {
    return items.where((item) {
      final matchesFilter =
          _filter == 'all' ||
          (widget.kind == StaffRecordKind.certificates
              ? _certificateStatus(item) == _filter
              : item['sourceType']?.toString() == _filter);
      final searchable = [
        item['id'],
        item['studentName'],
        item['studentId'],
        item['eventName'],
        item['className'],
        item['content'],
      ].join(' ').toLowerCase();
      return matchesFilter && searchable.contains(_query.trim().toLowerCase());
    }).toList();
  }

  /// Dựng nội dung tải, lỗi, rỗng và danh sách dữ liệu từ API.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);

    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final rawItems = snapshot.data?['items'];
        final items = rawItems is List
            ? rawItems.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        final filtered = _filteredItems(items);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              _buildHeading(colors, items.length),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError) ...[
                _buildSummary(colors, items),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildDistribution(colors, items),
                ],
                const SizedBox(height: 18),
              ],
              _buildFilters(colors, items),
              const SizedBox(height: 14),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                _buildMessage(
                  colors,
                  'Không tải được dữ liệu',
                  snapshot.error.toString(),
                  Icons.cloud_off_outlined,
                )
              else if (filtered.isEmpty)
                _buildMessage(
                  colors,
                  items.isEmpty ? 'Chưa có dữ liệu' : 'Không tìm thấy kết quả',
                  items.isEmpty
                      ? 'Danh sách sẽ hiển thị khi cơ sở dữ liệu có bản ghi.'
                      : 'Thử đổi từ khóa hoặc điều kiện lọc.',
                  Icons.inbox_outlined,
                )
              else
                ...filtered.map((item) => _buildRecord(colors, item)),
            ],
          ),
        );
      },
    );
  }

  /// Hiển thị tiêu đề và số bản ghi thực nhận từ backend.
  Widget _buildHeading(AppColors colors, int count) {
    final isCertificates = widget.kind == StaffRecordKind.certificates;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCertificates ? 'Chứng chỉ' : 'Phản hồi',
                style: AppTextStyles.displayLg(colors.foreground),
              ),
              const SizedBox(height: 5),
              Text(
                isCertificates
                    ? 'Tra cứu chứng chỉ đã ghi nhận theo sự kiện.'
                    : 'Ý kiến và đánh giá của sinh viên về sự kiện.',
                style: AppTextStyles.bodySm(colors.mutedForeground),
              ),
            ],
          ),
        ),
        Text(
          '$count bản ghi',
          style: AppTextStyles.bodySm(colors.mutedForeground),
        ),
      ],
    );
  }

  /// Tóm tắt số liệu được tính từ chính danh sách API trả về.
  Widget _buildSummary(AppColors colors, List<Map<String, dynamic>> items) {
    final isCertificates = widget.kind == StaffRecordKind.certificates;
    final secondaryCount = isCertificates
        ? items.where(_isCertificateIssued).length
        : items.where((item) => item['sourceType'] == 'Đánh giá').length;
    final secondaryLabel = isCertificates ? 'Đã cấp' : 'Đánh giá';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryTile(
          colors,
          'Tổng bản ghi',
          items.length,
          Icons.inventory_2_outlined,
        ),
        _summaryTile(
          colors,
          secondaryLabel,
          secondaryCount,
          isCertificates ? Icons.verified_outlined : Icons.star_outline,
        ),
      ],
    );
  }

  /// Nhóm bản ghi theo đúng trạng thái hoặc loại phản hồi trong dữ liệu API.
  Widget _buildDistribution(
    AppColors colors,
    List<Map<String, dynamic>> items,
  ) {
    final isCertificates = widget.kind == StaffRecordKind.certificates;
    final counts = <String, int>{};
    if (isCertificates) {
      counts['Đã cấp'] = items.where(_isCertificateIssued).length;
      counts['Chưa cấp'] = items.length - counts['Đã cấp']!;
    } else {
      for (final item in items) {
        final key = item['sourceType']?.toString() ?? 'Phản hồi';
        counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final labels = counts.keys.toList()..sort();
    final palette = [
      colors.primary,
      colors.success,
      colors.warning,
      colors.danger,
      colors.info,
    ];

    return StatisticsDonutChart(
      title: isCertificates
          ? 'Chứng chỉ theo trạng thái'
          : 'Phản hồi theo loại',
      colors: colors,
      data: [
        for (var index = 0; index < labels.length; index++)
          StatisticsChartDatum(
            label: labels[index],
            value: counts[labels[index]]!,
            color: palette[index % palette.length],
          ),
      ],
    );
  }

  /// Tạo một ô thống kê bằng số liệu truy vấn được.
  Widget _summaryTile(
    AppColors colors,
    String label,
    int value,
    IconData icon,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: AppTextStyles.displaySm(colors.foreground)),
              Text(label, style: AppTextStyles.bodyXs(colors.mutedForeground)),
            ],
          ),
        ],
      ),
    );
  }

  /// Hiển thị ô tìm kiếm cùng bộ lọc phù hợp với loại danh sách.
  Widget _buildFilters(AppColors colors, List<Map<String, dynamic>> items) {
    final isCertificates = widget.kind == StaffRecordKind.certificates;
    final options = isCertificates
        ? <String>['Đã cấp', 'Chưa cấp']
        : items
              .map((item) => item['sourceType']?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList();
    if (!isCertificates) options.sort();
    final selected = options.contains(_filter) ? _filter : 'all';

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: AppSearchField(
            colors: colors,
            hintText: 'Tìm mã, sinh viên, sự kiện...',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(
                  isCertificates ? 'Mọi trạng thái' : 'Mọi loại phản hồi',
                ),
              ),
              ...options.map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              ),
            ],
            onChanged: (value) => setState(() => _filter = value ?? 'all'),
          ),
        ),
      ],
    );
  }

  /// Chọn cách trình bày bản ghi theo loại màn hình.
  Widget _buildRecord(AppColors colors, Map<String, dynamic> item) {
    return widget.kind == StaffRecordKind.certificates
        ? _buildCertificate(colors, item)
        : _buildFeedback(colors, item);
  }

  /// Hiển thị một chứng chỉ cùng người nhận, sự kiện và trạng thái DB.
  Widget _buildCertificate(AppColors colors, Map<String, dynamic> item) {
    final status = _certificateStatus(item);
    final isIssued = _isCertificateIssued(item);
    final studentName =
        item['studentName']?.toString() ??
        item['studentId']?.toString() ??
        'Sinh viên';
    final studentId = item['studentId']?.toString() ?? '';
    final eventName = item['eventName']?.toString() ?? 'Sự kiện không xác định';
    final content = item['content']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  size: 22,
                  color: colors.secondaryForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          studentName,
                          style: AppTextStyles.displaySm(colors.foreground),
                        ),
                        Text(
                          studentId,
                          style: AppTextStyles.mono(
                            colors.mutedForeground,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      eventName,
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _statusLabel(colors, status),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _certificateMeta(
                        colors,
                        'Mã chứng chỉ',
                        item['id']?.toString() ?? '',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _certificateMeta(
                        colors,
                        'Ngày cấp',
                        _formatDate(item['issuedAt']),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nội dung',
                    style: AppTextStyles.bodyXs(colors.mutedForeground),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    content,
                    style: AppTextStyles.bodySm(colors.foreground)
                        .copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ],
          if (isIssued) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openCertificateDetails(item),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Xem chứng nhận'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openCertificateDetails(Map<String, dynamic> item) {
    final certificateId = item['id']?.toString() ?? '';
    if (certificateId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chứng nhận không có mã hợp lệ.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StaffCertificateDetailsPage(
          certificate: Map<String, dynamic>.from(item),
        ),
      ),
    );
  }

  Widget _certificateMeta(AppColors colors, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyXs(colors.mutedForeground)),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodySm(colors.foreground)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Hiển thị phản hồi hoặc đánh giá cùng nội dung gốc từ DB.
  Widget _buildFeedback(AppColors colors, Map<String, dynamic> item) {
    final rating = item['rating'];
    final source = item['sourceType']?.toString() ?? 'Phản hồi';
    final ratingText = rating == null ? source : '$source · $rating/5 sao';
    final eventName = item['eventName']?.toString() ?? '';
    final className = item['className']?.toString() ?? '';
    final contextName = eventName.isNotEmpty ? eventName : className;

    return _recordContainer(
      colors,
      leading: rating == null ? Icons.forum_outlined : Icons.star_outline,
      title: contextName.isEmpty ? 'Phản hồi chung' : contextName,
      subtitle:
          '${item['studentName'] ?? item['studentId'] ?? 'Sinh viên'} · ${item['studentId'] ?? ''}',
      trailing: _statusLabel(colors, ratingText),
      details: [
        _detail(colors, 'Gửi lúc', _formatDate(item['sentAt'])),
        if ((item['content']?.toString() ?? '').isNotEmpty)
          _detail(colors, 'Nội dung', item['content'].toString()),
      ],
    );
  }

  /// Dùng chung bố cục bản ghi, giữ nội dung dài có thể đọc trên màn hẹp.
  Widget _recordContainer(
    AppColors colors, {
    required IconData leading,
    required String title,
    required String subtitle,
    required Widget trailing,
    required List<Widget> details,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(leading, color: colors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.displaySm(colors.foreground),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[const SizedBox(height: 14), ...details],
        ],
      ),
    );
  }

  /// Tạo dòng chi tiết, tự xuống dòng với nội dung dài.
  Widget _detail(AppColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: AppTextStyles.bodyXs(colors.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodySm(colors.foreground)),
          ),
        ],
      ),
    );
  }

  /// Hiển thị trạng thái hoặc nhãn phân loại từ bản ghi API.
  Widget _statusLabel(AppColors colors, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTextStyles.bodyXs(colors.secondaryForeground),
      ),
    );
  }

  /// Hiển thị trạng thái lỗi hoặc danh sách rỗng mà không thêm dữ liệu mẫu.
  Widget _buildMessage(
    AppColors colors,
    String title,
    String message,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 38, color: colors.mutedForeground),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.displaySm(colors.foreground)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ],
      ),
    );
  }

  /// Định dạng ngày nhận từ MySQL và giữ nguyên khi dữ liệu không hợp lệ.
  String _formatDate(Object? value) {
    if (value == null) return 'Không có ngày';
    final parsed = DateTime.tryParse(value.toString());
    return parsed == null
        ? value.toString()
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }
}

class _StaffCertificateDetailsPage extends StatefulWidget {
  const _StaffCertificateDetailsPage({required this.certificate});

  final Map<String, dynamic> certificate;

  @override
  State<_StaffCertificateDetailsPage> createState() =>
      _StaffCertificateDetailsPageState();
}

class _StaffCertificateDetailsPageState
    extends State<_StaffCertificateDetailsPage> {
  late Future<Uint8List> _pdfFuture;

  @override
  void initState() {
    super.initState();
    _pdfFuture = _loadPdf();
  }

  String get _certificateId => widget.certificate['id']?.toString() ?? '';

  Future<Uint8List> _loadPdf() =>
      ApiClient().getBytes(ApiEndpoints.staffCertificatePdf(_certificateId));

  void _retry() {
    setState(() => _pdfFuture = _loadPdf());
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final studentName =
        widget.certificate['studentName']?.toString() ??
        widget.certificate['studentId']?.toString() ??
        'Sinh viên';
    final studentId = widget.certificate['studentId']?.toString() ?? '';
    final eventName = widget.certificate['eventName']?.toString() ?? 'Sự kiện';
    final eventId = widget.certificate['eventId']?.toString() ?? '';
    final location = widget.certificate['location']?.toString() ?? '';
    final content = widget.certificate['content']?.toString() ?? '';
    final startTime = DateTime.tryParse(
      widget.certificate['startTime']?.toString() ?? '',
    );
    final endTime = DateTime.tryParse(
      widget.certificate['endTime']?.toString() ?? '',
    );
    final issuedAt = DateTime.tryParse(
      widget.certificate['issuedAt']?.toString() ?? '',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết chứng nhận')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_outlined,
                        color: colors.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          eventName,
                          style: AppTextStyles.displaySm(colors.foreground),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _detailRow(colors, 'Người nhận', studentName),
                  if (studentId.isNotEmpty)
                    _detailRow(colors, 'Mã sinh viên', studentId),
                  _detailRow(colors, 'Mã chứng nhận', _certificateId),
                  if (eventId.isNotEmpty)
                    _detailRow(colors, 'Mã sự kiện', eventId),
                  _detailRow(
                    colors,
                    'Ngày cấp',
                    issuedAt == null
                        ? 'Chưa có thông tin'
                        : DateFormat('dd/MM/yyyy HH:mm')
                              .format(issuedAt.toLocal()),
                  ),
                  _detailRow(
                    colors,
                    'Trạng thái',
                    widget.certificate['status']?.toString() ?? 'Đã cấp',
                  ),
                  if (startTime != null)
                    _detailRow(
                      colors,
                      'Thời gian sự kiện',
                      endTime == null
                          ? DateFormat('dd/MM/yyyy HH:mm')
                                .format(startTime.toLocal())
                          : '${DateFormat('dd/MM/yyyy HH:mm').format(startTime.toLocal())} - '
                                '${DateFormat('dd/MM/yyyy HH:mm').format(endTime.toLocal())}',
                    ),
                  if (location.isNotEmpty)
                    _detailRow(colors, 'Địa điểm', location),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Nội dung',
                      style: AppTextStyles.bodyXs(colors.mutedForeground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content,
                      style: AppTextStyles.bodySm(colors.foreground),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Mẫu chứng nhận đã cấp',
            style: AppTextStyles.displaySm(colors.foreground),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 560,
            child: FutureBuilder<Uint8List>(
              future: _pdfFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Không thể tải mẫu chứng nhận: '
                            '${snapshot.error ?? 'Tệp rỗng.'}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySm(colors.mutedForeground),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final pdfBytes = snapshot.data!;
                return PdfPreview(
                  build: (_) async => pdfBytes,
                  maxPageWidth: 1000,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  useActions: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(AppColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodySm(colors.foreground)),
          ),
        ],
      ),
    );
  }
}
