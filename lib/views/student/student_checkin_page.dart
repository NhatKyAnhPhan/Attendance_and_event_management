import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/theme/app_colors.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../data/face/face_recognition_service.dart';

/// Mục 14 bản thiết kế — "Student Mobile: QR Scanner, Processing state,
/// Success, Expired QR, Invalid QR, Already checked in".
class StudentCheckinPage extends StatefulWidget {
  final bool isActive;

  const StudentCheckinPage({super.key, this.isActive = true});

  @override
  State<StudentCheckinPage> createState() => _StudentCheckinPageState();
}

enum _ScanState { idle, scanning, success, failed }

enum _ScanMethod { qr, face }

class _StudentCheckinPageState extends State<StudentCheckinPage>
    with SingleTickerProviderStateMixin {
  _ScanState _state = _ScanState.idle;
  _ScanMethod _method = _ScanMethod.qr;
  final _qrController = MobileScannerController();
  final _apiClient = ApiClient();
  final _secureStorage = const FlutterSecureStorage();
  Future<String>? _deviceIdFuture;
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _faceBusy = false;
  bool _faceDetected = false;
  bool _checkInBusy = false;
  bool _cameraErrorDialogVisible = false;
  Map<String, dynamic>? _checkInDetails;
  final Stopwatch _faceFrameClock = Stopwatch()..start();
  int _lastFaceFrameMs = 0;
  String? _errorMessage;
  late final AnimationController _lineCtrl;

  Future<String> _getDeviceId() {
    return _deviceIdFuture ??= _loadOrCreateDeviceId();
  }

  Future<String> _loadOrCreateDeviceId() async {
    const storageKey = 'attendanceDeviceId';
    final storedId = await _secureStorage.read(key: storageKey);
    if (storedId != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(storedId)) {
      return storedId;
    }

    final random = Random.secure();
    final deviceId = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _secureStorage.write(key: storageKey, value: deviceId);
    return deviceId;
  }

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StudentCheckinPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _reset();
    }
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    _qrController.dispose();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  // Hiển thị scanner; MobileScanner tự khởi động khi widget được gắn vào cây.
  void _startScan() {
    if (!widget.isActive || _state == _ScanState.scanning) return;
    setState(() {
      _state = _ScanState.scanning;
      _errorMessage = null;
    });
    if (_method == _ScanMethod.face) {
      _startFaceCamera();
    }
  }

  // Dừng scanner, camera và bộ nhận diện trước khi đổi trạng thái màn hình.
  Future<void> _stopCameras() async {
    await _qrController.stop();
    final camera = _cameraController;
    _cameraController = null;
    if (camera != null) {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      await camera.dispose();
    }
    await _faceDetector?.close();
    _faceDetector = null;
  }

  // Đưa quy trình điểm danh về trạng thái ban đầu.
  Future<void> _reset() async {
    await _stopCameras();
    if (!mounted) return;
    setState(() {
      _state = _ScanState.idle;
      _errorMessage = null;
      _checkInBusy = false;
      _faceDetected = false;
      _checkInDetails = null;
    });
  }

  Future<void> _retryScan() async {
    await _reset();
    if (!mounted) return;
    _startScan();
  }

  // Đổi phương thức điểm danh và giải phóng thiết bị đang sử dụng.
  Future<void> _setMethod(_ScanMethod method) async {
    await _stopCameras();
    if (!mounted) return;
    setState(() {
      _method = method;
      _state = _ScanState.idle;
      _errorMessage = null;
      _faceDetected = false;
      _faceBusy = false;
      _checkInBusy = false;
      _checkInDetails = null;
    });
  }

  // Khởi tạo camera trước và bắt đầu gửi từng khung hình cho bộ nhận diện.
  Future<void> _startFaceCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('Thiết bị không có camera.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableTracking: true,
        ),
      );
      await controller.initialize();
      if (!mounted || _state != _ScanState.scanning) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      setState(() {});
      await controller.startImageStream(_processFaceImage);
    } catch (error) {
      _cameraController = null;
      await controller?.dispose();
      await _faceDetector?.close();
      _faceDetector = null;
      if (!mounted) return;
      _showCameraUnavailableDialog();
    }
  }

  void _showCameraUnavailableDialog() {
    if (_cameraErrorDialogVisible) return;
    _cameraErrorDialogVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _cameraErrorDialogVisible = false;
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Không mở được camera'),
          content: const Text(
            'Không lấy được camera trên thiết bị. '
            'Vui lòng kiểm tra quyền camera rồi thử lại.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _state = _ScanState.idle;
        _errorMessage = null;
        _checkInBusy = false;
        _faceDetected = false;
      });
      _cameraErrorDialogVisible = false;
    });
  }

  // Chuyển dữ liệu camera sang ảnh ML Kit và gửi điểm danh khi phát hiện mặt.
  Future<void> _processFaceImage(CameraImage image) async {
    if (_faceBusy || _faceDetector == null || _cameraController == null) return;
    // Giới hạn tần suất nhận diện để giảm tải CPU và cấp phát bộ nhớ mỗi frame.
    final now = _faceFrameClock.elapsedMilliseconds;
    if (now - _lastFaceFrameMs < 250) return;
    _lastFaceFrameMs = now;
    _faceBusy = true;
    try {
      final byteCount = image.planes.fold<int>(
        0,
        (total, plane) => total + plane.bytes.length,
      );
      final bytes = Uint8List(byteCount);
      var offset = 0;
      for (final plane in image.planes) {
        bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(
                _cameraController!.description.sensorOrientation,
              ) ??
              InputImageRotation.rotation0deg,
          format:
              InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      final faces = await _faceDetector!.processImage(inputImage);
      if (mounted && faces.isNotEmpty && !_faceDetected) {
        setState(() => _faceDetected = true);
        await _submitFaceCheckIn();
      }
    } finally {
      _faceBusy = false;
    }
  }

  // Đọc token QR, lấy vị trí và gửi yêu cầu điểm danh đến backend.
  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_checkInBusy || _state != _ScanState.scanning) return;
    final token = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (token.isEmpty) return;

    _checkInBusy = true;
    try {
      await _qrController.stop();
      final isEventQr = _isEventAttendanceToken(token);
      final endpoint = isEventQr
          ? ApiEndpoints.eventAttendanceCheckIn
          : ApiEndpoints.attendanceCheckIn;
      final preview = await _apiClient.post(
        endpoint,
        data: {
          'qrToken': token,
          'preview': true,
          if (!isEventQr) 'method': 'QR',
        },
      );
      if (!mounted) return;
      setState(() => _checkInDetails = preview);
      final confirmed = await _showCheckInConfirmation();
      if (!confirmed) {
        await _reset();
        return;
      }
      if (!mounted) return;

      final position = await _getCurrentPosition();
      final deviceId = await _getDeviceId();
      final result = await _apiClient.post(
        endpoint,
        data: {
          'qrToken': token,
          'deviceId': deviceId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          if (!isEventQr) 'method': 'QR',
        },
      );
      if (mounted) {
        setState(() {
          _checkInDetails = result;
          _state = _ScanState.success;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _state = _ScanState.failed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể xử lý mã QR: $error';
        _state = _ScanState.failed;
      });
    }
  }

  bool _isEventAttendanceToken(String token) {
    final segments = token.split('.');
    if (segments.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      return payload is Map && payload['type'] == 'event-attendance';
    } on FormatException {
      return false;
    }
  }

  // Lấy thông tin xem trước rồi chỉ ghi nhận sau khi sinh viên xác nhận.
  Future<void> _submitFaceCheckIn() async {
    if (_checkInBusy) return;
    _checkInBusy = true;
    XFile? capturedImage;
    try {
      final camera = _cameraController;
      if (camera == null || !camera.value.isInitialized) {
        throw const ApiException('Camera chưa sẵn sàng để xác minh khuôn mặt.');
      }
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      capturedImage = await camera.takePicture();
      final recognizedStudentId = await FaceRecognitionService.recognize(
        capturedImage.path,
      );
      if (recognizedStudentId == null) {
        throw const ApiException(
          'Khuôn mặt không khớp với hồ sơ đã đăng ký.',
        );
      }
      await _stopCameras();
      final preview = await _apiClient.post(
        ApiEndpoints.attendanceFaceCheckIn,
        data: {
          'preview': true,
          'recognizedStudentId': recognizedStudentId,
        },
      );
      if (!mounted) return;
      setState(() => _checkInDetails = preview);
      final confirmed = await _showCheckInConfirmation();
      if (!confirmed) {
        await _reset();
        return;
      }
      if (!mounted) return;

      final position = await _getCurrentPosition();
      final deviceId = await _getDeviceId();
      final result = await _apiClient.post(
        ApiEndpoints.attendanceFaceCheckIn,
        data: {
          'recognizedStudentId': recognizedStudentId,
          'deviceId': deviceId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
      if (mounted) {
        setState(() {
          _checkInDetails = result;
          _state = _ScanState.success;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _state = _ScanState.failed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể xác minh khuôn mặt: $error';
        _state = _ScanState.failed;
      });
    } finally {
      _checkInBusy = false;
      if (capturedImage != null) {
        try {
          await File(capturedImage.path).delete();
        } on FileSystemException catch (error) {
          debugPrint('Could not remove temporary face image: $error');
        }
      }
    }
  }

  // Kiểm tra dịch vụ/quyền vị trí trước khi gửi tọa độ điểm danh.
  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException('Hãy bật dịch vụ vị trí để điểm danh.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ApiException('Cần cấp quyền vị trí để điểm danh.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(isDark);

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: _state != _ScanState.idle
                        ? IconButton(
                            tooltip: 'Thoát quét',
                            onPressed: _reset,
                            icon: const Icon(Icons.close, color: Colors.white),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      _method == _ScanMethod.qr
                          ? 'Điểm danh QR'
                          : 'Nhận diện khuôn mặt',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            if (_state == _ScanState.idle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildMethodSelector(),
              ),
            Expanded(
              child: switch (_state) {
                _ScanState.idle => _buildIdle(c),
                _ScanState.scanning =>
                  _method == _ScanMethod.qr
                      ? _buildScanningQr()
                      : _buildScanningFace(),
                _ScanState.success => _buildSuccess(c),
                _ScanState.failed => _buildFailed(c),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MethodButton(
              label: 'QR',
              icon: Icons.qr_code_scanner,
              active: _method == _ScanMethod.qr,
              onTap: () => _setMethod(_ScanMethod.qr),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MethodButton(
              label: 'Face',
              icon: Icons.face_retouching_natural,
              active: _method == _ScanMethod.face,
              onTap: () => _setMethod(_ScanMethod.face),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(AppColors c) {
    final title = _method == _ScanMethod.qr
        ? 'Nhấn nút bên dưới để bắt đầu quét mã QR điểm danh'
        : 'Nhấn nút bên dưới để bắt đầu nhận diện khuôn mặt';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _method == _ScanMethod.qr
                  ? Icons.qr_code_scanner
                  : Icons.face_retouching_natural,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _startScan,
              child: Text(
                _method == _ScanMethod.qr
                    ? 'Bắt đầu quét QR'
                    : 'Bắt đầu nhận diện',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningQr() {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _qrController,
          onDetect: _onQrDetected,
          errorBuilder: (context, error, child) {
            _showCameraUnavailableDialog();
            return const ColoredBox(color: Colors.black);
          },
        ),
        IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF16A34A), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 32,
          child: Text(
            'Đặt mã QR vào trong khung để điểm danh',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanningFace() {
    final camera = _cameraController;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              children: [
                if (camera != null && camera.value.isInitialized)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: CameraPreview(camera),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                if (_faceDetected)
                  const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Text(
                      'Đã phát hiện khuôn mặt. Đang chờ xác thực danh tính...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                if (camera == null)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                if (camera != null && !_faceDetected)
                  Center(
                    child: Container(
                      width: 160,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF60A5FA),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(80),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Icon(
                            Icons.face_6_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 82,
                          ),
                        ),
                      ),
                    ),
                  ),
                AnimatedBuilder(
                  animation: _lineCtrl,
                  builder: (context, child) => Positioned(
                    left: 18,
                    right: 18,
                    top: 20 + _lineCtrl.value * 200,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFF60A5FA),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Vui lòng nhìn thẳng vào camera để hệ thống nhận diện',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, String>> get _successDetails {
    final details = _checkInDetails ?? const <String, dynamic>{};
    final rows = <MapEntry<String, String>>[];
    void add(String label, Object? value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') rows.add(MapEntry(label, text));
    }

    final studentName = details['studentName']?.toString() ?? '';
    final studentId = details['studentId']?.toString() ?? '';
    add(
      'Sinh viên',
      [studentName, studentId].where((value) => value.isNotEmpty).join(' · '),
    );
    final classId =
        details['classId']?.toString() ?? details['eventId']?.toString() ?? '';
    final className =
        details['className']?.toString() ??
        details['eventName']?.toString() ??
        details['classOrEventName']?.toString() ??
        '';
    add(
      'Lớp / sự kiện',
      [classId, className].where((value) => value.isNotEmpty).join(' · '),
    );
    add('Buổi học', details['sessionName'] ?? details['classSessionId']);
    add('Giảng viên', details['lecturerName'] ?? details['organizerName']);
    add('Phòng / địa điểm', details['room'] ?? details['location']);
    final checkedInAt = DateTime.tryParse(
      details['checkedInAt']?.toString() ?? '',
    )?.toLocal();
    if (checkedInAt != null) {
      add('Giờ điểm danh', _formatDateTime(checkedInAt));
    }
    final start = DateTime.tryParse(details['startTime']?.toString() ?? '')
        ?.toLocal();
    final end = DateTime.tryParse(details['endTime']?.toString() ?? '')
        ?.toLocal();
    if (start != null || end != null) {
      add(
        'Thời gian buổi',
        [
          if (start != null) _formatDateTime(start),
          if (end != null) _formatDateTime(end),
        ].join(' - '),
      );
    }
    add('Trạng thái', details['status']);
    add('Hình thức', details['method']);
    return rows;
  }

  Future<bool> _showCheckInConfirmation() async {
    if (!mounted) return false;
    final details = _successDetails;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.fact_check_outlined),
            title: const Text('Xác nhận thông tin điểm danh'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vui lòng kiểm tra thông tin sinh viên và buổi điểm danh '
                      'dưới đây có chính xác không.',
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ...details.map(_buildConfirmationDetail),
                    ] else ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Không nhận được thông tin chi tiết từ máy chủ.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Nếu thông tin chưa đúng, vui lòng báo giảng viên hoặc ban '
                      'tổ chức để được hỗ trợ.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.check),
                label: const Text('Xác nhận điểm danh'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildConfirmationDetail(MapEntry<String, String> detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              detail.key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(detail.value)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$hour:$minute $day/$month/${value.year}';
  }

  String get _failureTitle {
    final message = _errorMessage ?? '';
    for (final category in [
      'Điểm danh thất bại',
      'Điểm danh thất bại',
      'Điểm danh thất bại',
    ]) {
      if (message.startsWith('$category:')) return category;
    }
    return 'Không thể xác thực';
  }

  Widget _buildSuccess(AppColors c) {
    final details = _successDetails;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Color(0xFF16A34A), size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Điểm danh thành công!',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: details
                    .map(
                      (detail) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 105,
                              child: Text(
                                detail.key,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                detail.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _reset,
              child: const Text('Quét lại'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Color(0xFFDC2626), size: 40),
          ),
          const SizedBox(height: 24),
          Text(
            _failureTitle,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ??
                (_method == _ScanMethod.qr
                    ? 'Mã QR không hợp lệ hoặc đã hết hạn.'
                    : 'Khuôn mặt chưa rõ nét, vui lòng thử lại.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _retryScan,
                  child: const Text('Thử lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _reset,
                  child: const Text('Làm mới'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _MethodButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? const Color(0xFF1E56A0) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF1E56A0) : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
