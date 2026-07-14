import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PronoShareService {
  /// Capture le widget pointé par [repaintKey] en PNG haute résolution
  /// et l'ouvre dans la feuille de partage native (WhatsApp, Telegram, etc.)
  static Future<void> captureAndShare({
    required GlobalKey repaintKey,
    required String shareText,
    double pixelRatio = 3.0,
  }) async {
    final boundary = repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('RepaintBoundary introuvable');

    final image    = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Impossible de convertir en PNG');

    final bytes = byteData.buffer.asUint8List();

    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/pronowin_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: shareText,
    );
  }
}
