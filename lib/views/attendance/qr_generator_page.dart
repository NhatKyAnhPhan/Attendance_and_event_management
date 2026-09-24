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

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

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
      setState(() {
        _qrToken = body['qr']?.toString();
        _expiresAt = DateTime.tryParse(body['closedAt']?.toString() ?? '');
        _lecturerPosition = position;
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
      appBar: AppBar(title: const Text('Tạo mã QR điểm danh')),
      backgroundColor: colors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Phiên học',
                  style: AppTextStyles.displaySm(colors.foreground),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedClassSession,
                  decoration: const InputDecoration(
                    labelText: 'Chọn buổi học để mở điểm danh',
                    border: OutlineInputBorder(),
                  ),
                  items: _sessions.map((session) {
                    final id = session['classSessionId']?.toString() ?? '';
                    final label = '${session['content'] ?? 'Buổi học'} · $id';
                    return DropdownMenuItem(value: id, child: Text(label));
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedClassSession = value),
                ),
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
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: colors.danger)),
                  const SizedBox(height: 8),
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
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.location_on, color: colors.success),
                      title: const Text('Vị trí điểm danh đã được khóa'),
                      subtitle: Text(
                        '${_lecturerPosition!.latitude.toStringAsFixed(6)}, '
                        '${_lecturerPosition!.longitude.toStringAsFixed(6)} · Phạm vi 150 m',
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      color: Colors.white,
                      child: QrImageView(data: _qrToken!, size: 260),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _expiresAt == null
                          ? 'QR đang hoạt động'
                          : 'Có hiệu lực đến ${_expiresAt!.hour.toString().padLeft(2, '0')}:${_expiresAt!.minute.toString().padLeft(2, '0')}',
                      style: AppTextStyles.bodySm(colors.mutedForeground),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
