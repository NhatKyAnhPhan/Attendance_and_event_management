import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';

/// Mục 14 bản thiết kế — "Student Mobile: QR Scanner, Processing state,
/// Success, Expired QR, Invalid QR, Already checked in".
class StudentCheckinPage extends StatefulWidget {
  const StudentCheckinPage({super.key});

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
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _faceBusy = false;
  bool _faceDetected = false;
  bool _checkInBusy = false;
  String? _errorMessage;
  late final AnimationController _lineCtrl;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    _qrController.dispose();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _state = _ScanState.scanning;
      _errorMessage = null;
    });
    if (_method == _ScanMethod.qr) {
      _qrController.start();
    } else {
      _startFaceCamera();
    }
  }

  void _reset() {
    _qrController.stop();
    _cameraController?.stopImageStream();
    setState(() {
      _state = _ScanState.idle;
      _errorMessage = null;
      _checkInBusy = false;
      _faceDetected = false;
    });
  }

  void _setMethod(_ScanMethod method) {
    _qrController.stop();
    _cameraController?.stopImageStream();
    setState(() {
      _method = method;
      _state = _ScanState.idle;
      _errorMessage = null;
      _faceDetected = false;
    });
  }

  Future<void> _startFaceCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
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
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể mở camera: $error';
        _state = _ScanState.failed;
      });
    }
  }

  Future<void> _processFaceImage(CameraImage image) async {
    if (_faceBusy || _faceDetector == null || _cameraController == null) return;
    _faceBusy = true;
    try {
      final bytes = Uint8List.fromList(
        image.planes.expand((plane) => plane.bytes).toList(),
      );
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(
                _cameraController!.description.sensorOrientation,
              ) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      final faces = await _faceDetector!.processImage(inputImage);
      if (mounted && faces.isNotEmpty && !_faceDetected) {
        setState(() => _faceDetected = true);
      }
    } finally {
      _faceBusy = false;
    }
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_checkInBusy || _state != _ScanState.scanning) return;
    final token = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (token.isEmpty) return;

    _checkInBusy = true;
    await _qrController.stop();
    try {
      await _apiClient.post(
        ApiEndpoints.attendanceCheckIn,
        data: {'qrToken': token, 'method': 'QR'},
      );
      if (mounted) setState(() => _state = _ScanState.success);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _state = _ScanState.failed;
      });
    }
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _method == _ScanMethod.qr ? 'Điểm danh QR' : 'Nhận diện khuôn mặt',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
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
                _ScanState.scanning => _method == _ScanMethod.qr
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
                _method == _ScanMethod.qr ? 'Bắt đầu quét QR' : 'Bắt đầu nhận diện',
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
        MobileScanner(controller: _qrController, onDetect: _onQrDetected),
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
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
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
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
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

  Widget _buildSuccess(AppColors c) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
          const SizedBox(height: 8),
          Text(
            _method == _ScanMethod.qr
                ? 'CS101 — Lập trình cơ bản'
                : 'Nhận diện khuôn mặt thành công — CS101',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} — ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
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
          const Text(
            'Không thể xác thực',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? (_method == _ScanMethod.qr
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
                  onPressed: _reset,
                  child: const Text('Thử lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _setMethod(_method),
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