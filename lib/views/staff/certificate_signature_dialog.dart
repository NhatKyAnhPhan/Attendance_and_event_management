import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';

class CertificateSignatureDialog extends StatefulWidget {
  const CertificateSignatureDialog({super.key});

  @override
  State<CertificateSignatureDialog> createState() =>
      _CertificateSignatureDialogState();
}

class _CertificateSignatureDialogState
    extends State<CertificateSignatureDialog> {
  final _client = ApiClient();
  final _deanNameController = TextEditingController();
  final _organizerNameController = TextEditingController();
  String _deanSignature = '';
  String _organizerSignature = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deanNameController.dispose();
    _organizerNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final result = await _client.get(ApiEndpoints.staffCertificateSignature);
      if (!mounted) return;
      setState(() {
        _deanSignature = result['signatureData']?.toString() ?? '';
        _organizerSignature =
            result['organizerSignatureData']?.toString() ?? '';
        _deanNameController.text = result['signatureName']?.toString() ?? '';
        _organizerNameController.text =
            result['organizerSignatureName']?.toString() ?? '';
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.put(
        ApiEndpoints.staffCertificateSignature,
        data: {
          'dean': {
            'imageData': _deanSignature,
            'name': _deanNameController.text.trim(),
          },
          'organizer': {
            'imageData': _organizerSignature,
            'name': _organizerNameController.text.trim(),
          },
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu chữ ký mẫu cho các chứng nhận mới.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Uint8List? _imageBytes(String data) {
    if (data.isEmpty) return null;
    final separator = data.indexOf(',');
    final encoded = separator >= 0 ? data.substring(separator + 1) : data;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chữ ký chứng nhận',
                      style: AppTextStyles.displaySm(colors.foreground),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        'Vẽ chữ ký và nhập tên người ký. Mẫu được dùng cho các chứng nhận cấp sau.',
                        style: AppTextStyles.bodySm(colors.mutedForeground),
                      ),
                      const SizedBox(height: 16),
                      _SignatureEditor(
                        title: 'Ban tổ chức',
                        nameController: _organizerNameController,
                        signatureData: _organizerSignature,
                        colors: colors,
                        onSignatureChanged: (value) =>
                            setState(() => _organizerSignature = value),
                        onError: (message) => setState(() => _error = message),
                        onClear: () => setState(() => _organizerSignature = ''),
                        imageBytes: _imageBytes(_organizerSignature),
                      ),
                      const SizedBox(height: 20),
                      _SignatureEditor(
                        title: 'Trưởng khoa',
                        nameController: _deanNameController,
                        signatureData: _deanSignature,
                        colors: colors,
                        onSignatureChanged: (value) =>
                            setState(() => _deanSignature = value),
                        onError: (message) => setState(() => _error = message),
                        onClear: () => setState(() => _deanSignature = ''),
                        imageBytes: _imageBytes(_deanSignature),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.danger),
                        ),
                      ),
                      if (_loadFailed)
                        TextButton(
                          onPressed: _loading ? null : _load,
                          child: const Text('Thử lại'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving || _loading || _loadFailed
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Đang lưu...' : 'Lưu chữ ký'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureEditor extends StatefulWidget {
  const _SignatureEditor({
    required this.title,
    required this.nameController,
    required this.signatureData,
    required this.colors,
    required this.onSignatureChanged,
    required this.onError,
    required this.onClear,
    required this.imageBytes,
  });

  final String title;
  final TextEditingController nameController;
  final String signatureData;
  final AppColors colors;
  final ValueChanged<String> onSignatureChanged;
  final ValueChanged<String> onError;
  final VoidCallback onClear;
  final Uint8List? imageBytes;

  @override
  State<_SignatureEditor> createState() => _SignatureEditorState();
}

class _SignatureEditorState extends State<_SignatureEditor> {
  int _padVersion = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chữ ký ${widget.title}',
          style: AppTextStyles.displaySm(widget.colors.foreground),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.nameController,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Tên hiển thị dưới chữ ký',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
        Row(
          children: [
            Text(
              widget.signatureData.isEmpty
                  ? 'Chưa có chữ ký'
                  : 'Chữ ký hiện tại',
              style: AppTextStyles.bodyXs(widget.colors.mutedForeground),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.signatureData.isEmpty
                  ? null
                  : () {
                      widget.onClear();
                      setState(() => _padVersion++);
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Xóa'),
            ),
          ],
        ),
        if (widget.imageBytes case final bytes?) ...[
          Container(
            height: 64,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: widget.colors.border),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Image.memory(
              bytes,
              height: 52,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text('Không thể xem chữ ký.'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SignaturePad(
          key: ValueKey(_padVersion),
          colors: widget.colors,
          onSignatureChanged: widget.onSignatureChanged,
          onError: widget.onError,
        ),
      ],
    );
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({
    super.key,
    required this.colors,
    required this.onSignatureChanged,
    required this.onError,
  });

  final AppColors colors;
  final ValueChanged<String> onSignatureChanged;
  final ValueChanged<String> onError;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];

  Future<void> _export(Size size) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(900 / size.width, 180 / size.height);
      _SignaturePainter(_strokes).paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, 180);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw StateError('Không thể tạo ảnh chữ ký.');
        }
        widget.onSignatureChanged(
          'data:image/png;base64,${base64Encode(byteData.buffer.asUint8List())}',
        );
      } finally {
        image.dispose();
      }
    } on Object catch (error) {
      widget.onError('Không thể tạo ảnh chữ ký: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 120);
        return GestureDetector(
          onPanStart: (details) => setState(() {
            _strokes.add([details.localPosition]);
          }),
          onPanUpdate: (details) => setState(() {
            _strokes.last.add(details.localPosition);
          }),
          onPanEnd: (_) => _export(size),
          child: Container(
            height: size.height,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: widget.colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              size: size,
              painter: _SignaturePainter(_strokes),
            ),
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF173C6B)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke, paint);
      } else if (stroke.length > 1) {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (final point in stroke.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      true;
}
