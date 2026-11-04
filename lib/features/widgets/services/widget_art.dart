import 'dart:typed_data';
import 'dart:ui' as ui;

/// Draws widget art off-screen and encodes it as PNG for RemoteViews.
Future<Uint8List> renderWidgetPng(
  ui.Size size,
  void Function(ui.Canvas canvas, ui.Size size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Offset.zero & size);
  paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
