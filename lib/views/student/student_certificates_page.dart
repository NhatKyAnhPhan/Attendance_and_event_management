// Sinh viên xem danh sách chứng nhận đã cấp và tải lại bản PDF trong ứng dụng.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';

class StudentCertificatesPage extends StatefulWidget {
  const StudentCertificatesPage({super.key});

  @override
  State<StudentCertificatesPage> createState() =>
      _StudentCertificatesPageState();
}

class _StudentCertificatesPageState extends State<StudentCertificatesPage> {
  late Future<Map<String, dynamic>> _certificatesFuture;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    _certificatesFuture = _loadCertificates();
  }

  Future<Map<String, dynamic>> _loadCertificates() =>
      ApiClient().get(ApiEndpoints.studentCertificates);

  Future<void> _refresh() async {
    final future = _loadCertificates();
    setState(() => _certificatesFuture = future);
    await future.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _downloadCertificate(Map<String, dynamic> certificate) async {
    final id = certificate['id']?.toString() ?? '';
    if (id.isEmpty || _downloadingId != null) return;

    setState(() => _downloadingId = id);
    try {
      final bytes = await ApiClient().getBytes(
        ApiEndpoints.studentCertificatePdf(id),
      );
      final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu chứng nhận',
        fileName: '$safeId.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chứng nhận đã được tải xuống.')),
        );
      } else if (path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã lưu chứng nhận tại $path')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể tải chứng nhận: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Chứng nhận của tôi')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _certificatesFuture,
        builder: (context, snapshot) {
          final rawItems = snapshot.data?['items'];
          final items = rawItems is List
              ? rawItems
                    .whereType<Map>()
                    .map(Map<String, dynamic>.from)
                    .toList()
              : <Map<String, dynamic>>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Chứng nhận được cấp cho tài khoản của bạn.',
                  style: AppTextStyles.bodySm(colors.mutedForeground),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  _MessageCard(
                    colors: colors,
                    icon: Icons.cloud_off_outlined,
                    message: 'Không thể tải danh sách: ${snapshot.error}',
                  )
                else if (items.isEmpty)
                  _MessageCard(
                    colors: colors,
                    icon: Icons.workspace_premium_outlined,
                    message: 'Bạn chưa có chứng nhận được cấp.',
                  )
                else
                  ...items.map((item) => _certificateCard(colors, item)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _certificateCard(AppColors colors, Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final eventName = item['eventName']?.toString() ?? 'Sự kiện';
    final issuedAt = DateTime.tryParse(item['issuedAt']?.toString() ?? '');
    final isDownloading = _downloadingId == id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        style: AppTextStyles.bodyMd(colors.foreground),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mã chứng nhận: $id',
                        style: AppTextStyles.bodySm(colors.mutedForeground),
                      ),
                      if (issuedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ngày cấp: ${DateFormat('dd/MM/yyyy').format(issuedAt.toLocal())}',
                          style: AppTextStyles.bodySm(colors.mutedForeground),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _downloadingId == null
                    ? () => _downloadCertificate(item)
                    : null,
                icon: isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(isDownloading ? 'Đang tải...' : 'Tải PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.colors,
    required this.icon,
    required this.message,
  });

  final AppColors colors;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colors.mutedForeground),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
