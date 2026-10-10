import 'dart:convert';

import 'package:flutter/services.dart';

class ExportSaveException implements Exception {
  const ExportSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Android Save screen reports success only after byte-for-byte readback.
class AndroidDocumentExport {
  const AndroidDocumentExport();

  static const _channel = MethodChannel('no_lean/export');

  Future<bool> save(
    String content, {
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('save', {
        'bytes': Uint8List.fromList(utf8.encode(content)),
        'fileName': fileName,
        'mimeType': mimeType,
      });
      if (saved == null) {
        throw const ExportSaveException('Saving did not complete. Try again.');
      }
      return saved;
    } on PlatformException catch (error) {
      throw ExportSaveException(switch (error.code) {
        'EXPORT_BUSY' => 'Finish the current export first.',
        'EXPORT_INTERRUPTED' => 'Export was interrupted. Try again.',
        'EXPORT_PICKER' => 'The Save screen could not open. Try again.',
        _ =>
          'The file could not be saved and checked. Try Downloads or another location. Your local data is intact.',
      });
    }
  }
}
