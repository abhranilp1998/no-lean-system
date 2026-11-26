import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Picks an image and copies it into the app's documents folder so the
/// goal jar can show it after the original is moved or deleted.
///
/// Returns the saved path, or null if the user cancelled. Throws on I/O
/// failures so the caller can show a notice. Not used in widget tests.
Future<String?> pickSavingsGoalPhoto() async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes =
      file.bytes ??
      (file.path != null ? await File(file.path!).readAsBytes() : null);
  if (bytes == null || bytes.isEmpty) {
    throw const FileSystemException('Could not read that photo.');
  }
  // Keep the copy small enough for a thumbnail.
  if (bytes.length > 8 * 1024 * 1024) {
    throw const FileSystemException('Choose a photo under 8 MB.');
  }
  if (kIsWeb) return null;
  final dir = await getApplicationDocumentsDirectory();
  final ext = _safeExt(file.extension ?? file.name);
  final name =
      'savings_goal_${DateTime.now().millisecondsSinceEpoch}_'
      '${Random().nextInt(1 << 16)}.$ext';
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

String _safeExt(String raw) {
  final cleaned = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  const ok = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};
  if (ok.contains(cleaned)) return cleaned == 'jpeg' ? 'jpg' : cleaned;
  return 'jpg';
}
