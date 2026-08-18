import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import 'remote_config_service.dart';

/// Vérification de version au démarrage.
///
/// Le renvoi dépend du canal, et c'est tout l'objet de ce service :
///
///  - **store** : le binaire vient d'App Store ou de Google Play, les seuils
///    viennent de Remote Config, le bouton ouvre la fiche du store.
///  - **direct** : l'APK vient du site et ne se met jamais à jour tout seul.
///    Les seuils et l'URL du fichier viennent de `GET /config`, et le bouton
///    lance le téléchargement.
///
/// La version précédente ne connaissait qu'un seul chemin : elle envoyait tout
/// le monde sur le Play Store. Un utilisateur ayant installé l'APK depuis le
/// site atterrissait donc sur une fiche qui n'a pas son build — au mieux une
/// impasse, au pire une bascule silencieuse vers la version store, qui n'offre
/// pas le paiement Mobile Money par lequel il a payé.
class VersionService {
  /// Seuils et destination de mise à jour, une fois le canal résolu.
  static Future<void> check(
    BuildContext context, {
    required bool estStore,
    required Dio dio,
  }) async {
    try {
      final pkg     = await PackageInfo.fromPlatform();
      final courante = _parse(pkg.version);

      // La maintenance vaut pour les deux canaux et prime sur tout le reste.
      if (RemoteConfigService.maintenanceMode) {
        if (!context.mounted) return;
        await _afficher(context,
          message:  RemoteConfigService.maintenanceMsg,
          bloquant: true,
          titre:    'Maintenance en cours',
          lien:     null);
        return;
      }

      final seuils = estStore
          ? _Seuils(
              min:     RemoteConfigService.minVersion,
              latest:  RemoteConfigService.latestVersion,
              force:   RemoteConfigService.forceUpdate,
              message: RemoteConfigService.updateMessage,
              lien:    Platform.isIOS
                  ? AppConstants.appStoreUrl
                  : AppConstants.playStoreUrl,
            )
          : await _seuilsDirects(dio);

      // Canal direct sans URL d'APK configurée : inviter à mettre à jour sans
      // pouvoir fournir le fichier n'aiderait personne.
      if (seuils == null || seuils.lien == null || seuils.lien!.isEmpty) return;

      final obligatoire = _comparer(courante, _parse(seuils.min)) < 0 || seuils.force;
      final disponible  = _comparer(courante, _parse(seuils.latest)) < 0;
      if (!obligatoire && !disponible) return;

      // Une mise à jour facultative ne se rappelle qu'une fois par version :
      // la redemander à chaque lancement finit par apprendre à l'utilisateur
      // à fermer la fenêtre sans la lire.
      if (!obligatoire && await _dejaIgnoree(seuils.latest)) return;

      if (!context.mounted) return;
      final reponse = await _afficher(context,
        message:  seuils.message,
        bloquant: obligatoire,
        lien:     seuils.lien);

      if (!obligatoire && reponse == _Reponse.plusTard) {
        await _memoriserIgnoree(seuils.latest);
      }
    } catch (_) {
      // Silencieux — la vérification de version ne doit jamais bloquer l'app.
    }
  }

  /// Seuils du canal direct, lus sur l'API publique.
  static Future<_Seuils?> _seuilsDirects(Dio dio) async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/config');
      final d = r.data;
      if (d == null) return null;
      return _Seuils(
        min:     (d['apkMinVersion']    as String?) ?? '1.0.0',
        latest:  (d['apkLatestVersion'] as String?) ?? '1.0.0',
        force:   (d['apkForceUpdate']   as bool?)   ?? false,
        message: (d['updateMessage']    as String?) ??
            'Une nouvelle version de PronoWin est disponible.',
        lien:    d['apkUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Mémoire des refus ─────────────────────────────────────────────────
  static String _cle(String version) => 'maj_ignoree_$version';

  static Future<bool> _dejaIgnoree(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_cle(version)) ?? false;
    } catch (_) { return false; }
  }

  static Future<void> _memoriserIgnoree(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cle(version), true);
    } catch (_) { /* sans mémoire, on redemandera : sans gravité */ }
  }

  // ─── Boîte de dialogue ─────────────────────────────────────────────────
  static Future<_Reponse?> _afficher(
    BuildContext context, {
    required String message,
    required bool bloquant,
    required String? lien,
    String? titre,
  }) {
    return showDialog<_Reponse>(
      context:            context,
      barrierDismissible: !bloquant,
      builder: (ctx) => PopScope(
        canPop: !bloquant,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            titre ?? (bloquant ? 'Mise à jour requise' : 'Mise à jour disponible'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(message,
            style: const TextStyle(fontSize: 14, height: 1.5)),
          actions: [
            if (!bloquant)
              TextButton(
                onPressed: () => Navigator.pop(ctx, _Reponse.plusTard),
                child: const Text('Plus tard')),
            FilledButton(
              onPressed: () async {
                if (lien != null && lien.isNotEmpty) {
                  try {
                    await launchUrl(Uri.parse(lien),
                        mode: LaunchMode.externalApplication);
                  } catch (_) { /* rien de mieux à proposer ici */ }
                }
                if (ctx.mounted) Navigator.pop(ctx, _Reponse.majFaite);
              },
              child: Text(lien == null ? 'OK' : 'Mettre à jour')),
          ],
        ),
      ),
    );
  }

  // ─── Comparaison sémantique ────────────────────────────────────────────
  static List<int> _parse(String v) {
    // `1.4.2+18` : le numéro de build après « + » ne participe pas à l'ordre.
    final noyau = v.split('+').first;
    final parts = noyau.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }

  static int _comparer(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}

enum _Reponse { plusTard, majFaite }

class _Seuils {
  final String min;
  final String latest;
  final bool   force;
  final String message;
  final String? lien;

  const _Seuils({
    required this.min,
    required this.latest,
    required this.force,
    required this.message,
    required this.lien,
  });
}
