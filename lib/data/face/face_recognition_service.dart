import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognitionService {
  FaceRecognitionService._(
    this._interpreter,
    this._detector,
    this._templatesByStudent,
  );

  static const _profiles = <String, String>{
    '2001230097': 'facedataset/Dieu/',
    '2001230787': 'facedataset/Tam/',
    '2001230014': 'facedataset/KyAnh/',
  };
  static const _matchThreshold = 0.8;
  static const _maxTemplatesPerPerson = 12;
  static const _faceSize = 112;
  static const _embeddingSize = 192;

  static FaceRecognitionService? _instance;
  static Future<FaceRecognitionService>? _initialization;

  final Interpreter _interpreter;
  final FaceDetector _detector;
  final Map<String, List<List<double>>> _templatesByStudent;

  static Future<FaceRecognitionService> _getInstance() async {
    final instance = _instance;
    if (instance != null) return instance;
    final initialization = _initialization;
    if (initialization != null) return initialization;

    final future = _create();
    _initialization = future;
    try {
      final created = await future;
      _instance = created;
      return created;
    } finally {
      _initialization = null;
    }
  }

  static Future<String?> recognize(String imagePath) async {
    final service = await _getInstance();
    final imageFile = File(imagePath);
    final bytes = await imageFile.readAsBytes();
    final faces = await service._detector.processImage(
      InputImage.fromFilePath(imagePath),
    );
    if (faces.length != 1) {
      throw StateError(
        faces.isEmpty
            ? 'Không tìm thấy khuôn mặt rõ ràng.'
            : 'Khung hình phải chỉ có một khuôn mặt.',
      );
    }

    final probe = await service._embed(bytes, faces.single.boundingBox);
    var bestSimilarity = -1.0;
    String? bestStudentId;
    for (final entry in service._templatesByStudent.entries) {
      for (final template in entry.value) {
        final similarity = _cosineSimilarity(probe, template);
        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestStudentId = entry.key;
        }
      }
    }
    return bestSimilarity >= _matchThreshold ? bestStudentId : null;
  }

  static Future<FaceRecognitionService> _create() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      'assets/models/mobilefacenet.tflite',
      options: options,
    );
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (inputShape.length != 4 ||
        inputShape[0] != 1 ||
        inputShape[1] != _faceSize ||
        inputShape[2] != _faceSize ||
        inputShape[3] != 3 ||
        outputShape.length != 2 ||
        outputShape[0] != 1 ||
        outputShape[1] != _embeddingSize) {
      interpreter.close();
      throw StateError('Model khuôn mặt không có định dạng được hỗ trợ.');
    }

    final detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();
      final samplePathsByStudent = <String, List<String>>{};
      for (final entry in _profiles.entries) {
        final samplePaths =
            assets
                .where(
                  (path) =>
                      path.startsWith(entry.value) &&
                      RegExp(
                        r'\.(png|jpe?g)$',
                        caseSensitive: false,
                      ).hasMatch(path),
                )
                .toList()
              ..sort();
        if (samplePaths.isEmpty) {
          throw StateError('Không có ảnh mẫu cho sinh viên ${entry.key}.');
        }
        samplePathsByStudent[entry.key] = _selectRepresentativeSamples(
          samplePaths,
        );
      }

      final tempDirectory = await Directory.systemTemp.createTemp(
        'dieutruong_face_samples_',
      );
      final templatesByStudent = <String, List<List<double>>>{};
      var rejectedSamples = 0;
      var totalSamples = 0;
      try {
        for (final entry in samplePathsByStudent.entries) {
          final templates = <List<double>>[];
          for (var index = 0; index < entry.value.length; index++) {
            final samplePath = entry.value[index];
            totalSamples++;
            final data = await rootBundle.load(samplePath);
            final extension = samplePath.substring(samplePath.lastIndexOf('.'));
            final sampleFile = File(
              '${tempDirectory.path}${Platform.pathSeparator}'
              'sample${entry.key}$index$extension',
            );
            await sampleFile.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true,
            );
            try {
              final faces = await detector.processImage(
                InputImage.fromFilePath(sampleFile.path),
              );
              if (faces.length != 1) {
                rejectedSamples++;
                continue;
              }
              templates.add(
                await _embedImage(
                  interpreter,
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                  faces.single.boundingBox,
                ),
              );
            } on Exception {
              rejectedSamples++;
            }
          }
          if (templates.isEmpty) {
            throw StateError('Không thể tạo mẫu nhận diện cho ${entry.key}.');
          }
          templatesByStudent[entry.key] = templates;
        }
      } finally {
        await tempDirectory.delete(recursive: true);
      }

      if (rejectedSamples > 0) {
        debugPrint(
          'Face enrollment skipped $rejectedSamples of '
          '$totalSamples unusable sample images.',
        );
      }
      return FaceRecognitionService._(
        interpreter,
        detector,
        templatesByStudent,
      );
    } catch (error, stackTrace) {
      await detector.close();
      interpreter.close();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static List<String> _selectRepresentativeSamples(List<String> paths) {
    if (paths.length <= _maxTemplatesPerPerson) return paths;
    return List.generate(
      _maxTemplatesPerPerson,
      (index) =>
          paths[index * (paths.length - 1) ~/ (_maxTemplatesPerPerson - 1)],
    );
  }

  Future<List<double>> _embed(Uint8List bytes, ui.Rect faceBounds) =>
      _embedImage(_interpreter, bytes, faceBounds);

  static Future<List<double>> _embedImage(
    Interpreter interpreter,
    Uint8List bytes,
    ui.Rect faceBounds,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final imageBounds = ui.Rect.fromLTWH(
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
      );
      final crop = faceBounds.intersect(imageBounds);
      if (crop.width < 1 || crop.height < 1) {
        throw StateError('Không đọc được vùng khuôn mặt trong ảnh.');
      }

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        crop,
        ui.Rect.fromLTWH(0, 0, _faceSize.toDouble(), _faceSize.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final resized = await recorder.endRecording().toImage(
        _faceSize,
        _faceSize,
      );
      try {
        final pixelData = await resized.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixelData == null) {
          throw StateError('Không thể xử lý ảnh khuôn mặt.');
        }

        final input = List.generate(
          1,
          (_) => List.generate(
            _faceSize,
            (y) => List.generate(_faceSize, (x) {
              final offset = (y * _faceSize + x) * 4;
              return <double>[
                (pixelData.getUint8(offset) - 127.5) / 127.5,
                (pixelData.getUint8(offset + 1) - 127.5) / 127.5,
                (pixelData.getUint8(offset + 2) - 127.5) / 127.5,
              ];
            }),
          ),
        );
        final output = List.generate(
          1,
          (_) => List<double>.filled(_embeddingSize, 0),
        );
        interpreter.run(input, output);
        return output.single;
      } finally {
        resized.dispose();
      }
    } finally {
      source.dispose();
      codec.dispose();
    }
  }

  static double _cosineSimilarity(List<double> first, List<double> second) {
    var dot = 0.0;
    var firstNorm = 0.0;
    var secondNorm = 0.0;
    for (var index = 0; index < first.length; index++) {
      dot += first[index] * second[index];
      firstNorm += first[index] * first[index];
      secondNorm += second[index] * second[index];
    }
    if (firstNorm == 0 || secondNorm == 0) return -1;
    return dot / math.sqrt(firstNorm * secondNorm);
  }
}
