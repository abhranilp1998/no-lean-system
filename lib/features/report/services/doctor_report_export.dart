import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../recovery/services/android_document_export.dart';

const pdfMimeType = 'application/pdf';

/// Hands a finished PDF to the user, and only when they tap Save or Share.
/// Nothing is uploaded: Save writes to a place they pick, Share opens the
/// system share sheet so they choose where it goes.
class DoctorReportExporter {
  DoctorReportExporter({
    Future<bool> Function(Uint8List bytes, String fileName)? saveBytes,
    Future<ShareResult> Function(ShareParams)? share,
    Future<Directory> Function()? temporaryDirectory,
  }) : _saveBytes = saveBytes ?? _saveWithSystemScreen,
       _share = share ?? SharePlus.instance.share,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<bool> Function(Uint8List bytes, String fileName) _saveBytes;
  final Future<ShareResult> Function(ShareParams) _share;
  final Future<Directory> Function() _temporaryDirectory;

  /// Android's Save screen (verified readback), the document picker on
  /// iOS, a save dialog elsewhere. Returns false when the user cancels.
  Future<bool> save(Uint8List bytes, String fileName) =>
      _saveBytes(bytes, fileName);

  /// Opens the share sheet with a temporary copy. Old temporary copies are
  /// removed on the next share, never right away, so the receiving app can
  /// still read the file.
  Future<void> share(Uint8List bytes, String fileName) async {
    final root = await _temporaryDirectory();
    final dir = Directory('${root.path}/exports');
    if (await dir.exists()) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final entity in dir.list()) {
        if (entity is File && (await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } else {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await _share(ShareParams(files: [XFile(file.path, mimeType: pdfMimeType)]));
  }

  static Future<bool> _saveWithSystemScreen(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!kIsWeb && Platform.isAndroid) {
      return const AndroidDocumentExport().saveBytes(
        bytes,
        fileName: fileName,
        mimeType: pdfMimeType,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save doctor summary',
        fileName: fileName,
        type: FileType.any,
        bytes: bytes,
      );
      return path != null;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save doctor summary',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (path == null) return false;
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }
}
