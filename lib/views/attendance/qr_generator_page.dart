import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';

class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key});

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  final _client = ApiClient();
  List<Map<String, dynamic>> _sessions = [];
  String? _selectedClassSession;
  String? _qrToken;
  DateTime? _expiresAt;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  Position? _lecturerPosition;
  int? _radiusMeters;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  // Tải các buổi học mà giảng viên có thể mở điểm danh.
  Future<void> _loadSessions() async {
    try {
      final body = await _client.get(ApiEndpoints.attendanceSessions);
      final items = body['items'];
      if (!mounted) return;
      setState(() {
        _sessions = items is List
            ? items
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList()
            : [];
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  // Lấy vị trí hiện tại và tạo phiên điểm danh kèm mã QR từ API.
  Future<void> _createQr() async {
    if (_selectedClassSession == null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final position = await _getCurrentPosition();
      final body = await _client.post(
        ApiEndpoints.attendanceSessions,
        data: {
          'classSessionId': _selectedClassSession,
          'method': 'Both',
          'durationMinutes': 15,
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
      if (!mounted) return;
      final radiusMeters = body['radiusMeters'];
      if (radiusMeters is! num) {
        throw const ApiException('Máy chủ không trả về phạm vi điểm danh.');
      }
      setState(() {
        _qrToken = body['qr']?.toString();
        _expiresAt = DateTime.tryParse(body['closedAt']?.toString() ?? '');
        _lecturerPosition = position;
        _radiusMeters = radiusMeters.toInt();
        _creating = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _creating = false;
      });
    }
  }

  // Kiểm tra dịch vụ/quyền vị trí trước khi tạo phiên điểm danh.
  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException(
        'Hãy bật dịch vụ vị trí trên thiết bị giảng viên.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ApiException('Cần cấp quyền vị trí để mở điểm danh.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(isDark);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tạo mã QR điểm danh',
          style: AppTextStyles.displayMd(colors.foreground),
        ),
      ),
      backgroundColor: colors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 1000;
                final content = desktop
                    ? SizedBox(
                        height: constraints.maxHeight - 40,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 44,
                              child: _buildSessionPanel(colors, scroll: true),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 56,
                              child: _buildQrPanel(colors, scroll: true),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildSessionPanel(colors, scroll: false),
                            const SizedBox(height: 16),
                            _buildQrPanel(colors, scroll: false),
                          ],
                        ),
                      );
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: content,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSessionPanel(AppColors colors, {required bool scroll}) {
    final items = _sessions
        .map((session) => _buildSessionItem(colors, session))
        .toList();
    final list = scroll
        ? Expanded(
            child: Scrollbar(
              child: ListView(padding: EdgeInsets.zero, children: items),
            ),
          )
        : Column(children: items);
    return _panel(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Phiên học',
                style: AppTextStyles.displaySm(colors.foreground),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chọn buổi học để mở điểm danh',
            style: AppTextStyles.bodySm(colors.mutedForeground),
          ),
          const SizedBox(height: 14),
          list,
        ],
      ),
    );
  }

  Widget _buildSessionItem(AppColors colors, Map<String, dynamic> session) {
    final id = session['classSessionId']?.toString() ?? '';
    final classId = session['classId']?.toString() ?? '';
    final className = session['className']?.toString().trim();
    final subjectName = session['subjectName']?.toString().trim();
    final classLabel = className?.isNotEmpty == true
        ? className!
        : 'Không có tên lớp ($classId)';
    final selected = _selectedClassSession == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? colors.secondary : colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: colors.primary.withValues(alpha: 0.045),
          onTap: () => setState(() => _selectedClassSession = id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.primary : colors.border,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withValues(alpha: 0.1)
                        : colors.muted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classLabel,
                        style: AppTextStyles.displaySm(colors.foreground),
                      ),
                      if (subjectName?.isNotEmpty == true) ...[
                        const SizedBox(height: 5),
                        _metadataLine(
                          colors,
                          Icons.book_outlined,
                          subjectName!,
                        ),
                      ],
                      const SizedBox(height: 5),
                      _metadataLine(
                        colors,
                        Icons.calendar_today_outlined,
                        'Buổi $id',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrPanel(AppColors colors, {required bool scroll}) {
    Map<String, dynamic>? selectedSession;
    for (final session in _sessions) {
      if (session['classSessionId']?.toString() == _selectedClassSession) {
        selectedSession = session;
        break;
      }
    }
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSession != null)
          _buildSelectedSession(colors, selectedSession),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: colors.danger)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : _loadSessions,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử kết nối lại'),
            ),
          ),
        ],
        if (_qrToken != null) ...[
          if (_lecturerPosition != null) ...[
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_on, color: colors.success),
              title: const Text('Vị trí điểm danh đã được khóa'),
              subtitle: Text(
                '${_lecturerPosition!.latitude.toStringAsFixed(6)}, '
                '${_lecturerPosition!.longitude.toStringAsFixed(6)} · '
                'Phạm vi ${_radiusMeters ?? '--'} m',
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(data: _qrToken!, size: 230),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _expiresAt == null
                  ? 'QR đang hoạt động'
                  : 'Có hiệu lực đến ${_expiresAt!.hour.toString().padLeft(2, '0')}:${_expiresAt!.minute.toString().padLeft(2, '0')}',
              style: AppTextStyles.bodySm(colors.mutedForeground),
            ),
          ),
        ] else
          SizedBox(
            height: 230,
            child: Center(
              child: Icon(
                Icons.qr_code_2_rounded,
                size: 88,
                color: colors.border,
              ),
            ),
          ),
      ],
    );
    return _panel(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scroll)
            Expanded(child: SingleChildScrollView(child: details))
          else
            details,
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _creating || _selectedClassSession == null
                ? null
                : _createQr,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2),
            label: const Text('Mở phiên và tạo QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSession(AppColors colors, Map<String, dynamic> session) {
    final id = session['classSessionId']?.toString() ?? '';
    final classId = session['classId']?.toString() ?? '';
    final className = session['className']?.toString().trim();
    final subjectName = session['subjectName']?.toString().trim();
    final classLabel = className?.isNotEmpty == true
        ? className!
        : 'Không có tên lớp ($classId)';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondary,
        border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.book_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classLabel,
                  style: AppTextStyles.displaySm(colors.foreground),
                ),
                if (subjectName?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    subjectName!,
                    style: AppTextStyles.bodyXs(colors.mutedForeground),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Buổi $id',
                  style: AppTextStyles.bodyXs(colors.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadataLine(AppColors colors, IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: colors.mutedForeground),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyXs(colors.mutedForeground),
          ),
        ),
      ],
    );
  }

  Widget _panel(AppColors colors, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
