import 'dart:io';

import 'package:flutter/foundation.dart';

Future<void> deleteTemporaryImage(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException catch (error) {
    debugPrint('Could not remove temporary face image: $error');
  }
}
