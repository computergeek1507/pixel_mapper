import 'dart:typed_data';
import 'dart:ui';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/wired_model.dart';
import '../widgets/wiring_canvas.dart';

/// Renders the full wiring diagram (not whatever's currently visible in the
/// on-screen pan/zoomed viewport — [WiringPainter] always draws the whole
/// model fit-to-canvas, so this reuses it directly at a fixed offscreen
/// size) to a PNG, then hands a one-page PDF of it to the platform print
/// dialog.
Future<void> printWiringDiagram(
  WiredModel model, {
  required bool showLabels,
  required bool showBackside,
}) async {
  final pngBytes = await _renderPng(
    model,
    showLabels: showLabels,
    showBackside: showBackside,
  );
  final image = pw.MemoryImage(pngBytes);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              model.name,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${model.displayAs} · ${model.nodes.length} nodes · '
              '${showBackside ? "Backside (wiring) view" : "Front/display view"}',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            pw.Expanded(child: pw.Center(child: pw.Image(image))),
          ],
        );
      },
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

Future<Uint8List> _renderPng(
  WiredModel model, {
  required bool showLabels,
  required bool showBackside,
}) async {
  const size = 1600.0;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  WiringPainter(
    model: model,
    showLabels: showLabels,
    showBackside: showBackside,
    forPrint: true,
  ).paint(canvas, const Size(size, size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
