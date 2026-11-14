import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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

    await partagerFichiers(
      [XFile(file.path, mimeType: 'image/png')],
      texte: shareText,
      origine: _origine(boundary),
    );
  }

  /// Partage des fichiers, avec leur texte là où il ne les fait pas perdre.
  ///
  /// ── L'image n'arrivait pas sur iPhone ─────────────────────────────────
  ///
  /// Le PNG et le message partaient ensemble. Android remet les deux à
  /// l'application choisie ; sur iOS, la feuille de partage les présente comme
  /// deux éléments, et WhatsApp — comme d'autres — n'en garde qu'un : le
  /// texte. Le destinataire recevait le lien, sans la carte du pronostic.
  ///
  /// Sur iOS, le fichier part donc seul. L'image porte déjà le domaine en pied
  /// de carte ; le texte, lui, reste disponible par le bouton « Copier ».
  static Future<void> partagerFichiers(
    List<XFile> fichiers, {
    String? texte,
    Rect? origine,
  }) =>
      Share.shareXFiles(
        fichiers,
        text: texteAvecFichiers(texte, defaultTargetPlatform),
        sharePositionOrigin: origine,
      );

  /// Le texte à joindre aux fichiers sur [plateforme] — aucun sur iOS.
  @visibleForTesting
  static String? texteAvecFichiers(String? texte, TargetPlatform plateforme) =>
      plateforme == TargetPlatform.iOS ? null : texte;

  /// Où ancrer la feuille de partage : Apple l'exige sur iPad, et la
  /// recommande partout. Le rectangle de la carte capturée, à l'écran.
  static Rect? _origine(RenderBox boite) {
    if (!boite.hasSize || !boite.attached) return null;
    final coin = boite.localToGlobal(Offset.zero);
    final zone = coin & boite.size;
    return zone.isEmpty ? null : zone;
  }
}
