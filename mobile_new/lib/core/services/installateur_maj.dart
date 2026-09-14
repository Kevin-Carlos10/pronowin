import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Ce que l'installateur du système a répondu.
enum ResultatInstallation {
  /// L'installateur s'est ouvert. L'application va être remplacée.
  ouvert,

  /// L'utilisateur a été envoyé vers le réglage « installer des applications
  /// inconnues ». Il faudra réessayer à son retour.
  autorisationDemandee,

  /// Ce paquet ne peut pas s'installer lui-même — typiquement parce qu'il vient
  /// d'une boutique, et se met à jour par elle.
  impossible,
}

/// Télécharge la nouvelle version et la remet à l'installateur.
///
/// L'APK distribué depuis le site ne se met pas à jour tout seul. Jusqu'ici, la
/// seule voie proposée était d'ouvrir l'adresse dans le navigateur :
/// l'utilisateur quittait l'application, attendait soixante-dix mégaoctets sans
/// savoir où il en était, cherchait le fichier dans ses téléchargements — et
/// revenait, ou ne revenait pas. Pendant tout ce temps, l'écran de blocage
/// restait affiché derrière, sans rien dire.
///
/// L'application télécharge donc elle-même, montre où elle en est, et ouvre
/// l'installateur à la fin.
///
/// ── Canal direct uniquement ────────────────────────────────────────────────
///
/// Rien de tout cela ne vaut pour le paquet des boutiques : installer un APK
/// hors Play est réservé aux boutiques d'applications par la politique
/// « Device and Network Abuse ». La permission n'est déclarée que dans la
/// variante `direct` (voir `android/app/src/direct/AndroidManifest.xml`), et le
/// code natif refuse d'agir sans elle.
class InstallateurMaj {
  /// Nom du canal, à tenir identique côté Kotlin (`InstallateurApk.CANAL`).
  @visibleForTesting
  static const MethodChannel canal =
      MethodChannel('com.pronowin.app/installateur');

  /// Nom du fichier téléchargé, dans le sous-dossier exposé au fournisseur.
  ///
  /// Le chemin doit rester sous `maj/` : c'est tout ce que
  /// `chemins_installateur.xml` autorise le fournisseur à partager, et un
  /// fichier posé ailleurs ferait échouer l'ouverture avec une exception
  /// d'argument illisible pour l'utilisateur.
  static const String _sousDossier = 'maj';
  static const String _nomFichier = 'pronowin-maj.apk';

  /// Télécharge [url] en rapportant l'avancement entre 0 et 1.
  ///
  /// Le client est neuf, et volontairement pas celui de l'application : les
  /// intercepteurs de celle-ci ajoutent un jeton d'authentification, une URL de
  /// base et un cache de réponses JSON. Aucun n'a de sens pour un binaire de
  /// soixante-dix mégaoctets servi par le site.
  static Future<File> telecharger(
    String url, {
    required void Function(double) progression,
    CancelToken? annulation,
    Dio? client,
  }) async {
    final dossier = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$_sousDossier',
    );
    if (!await dossier.exists()) {
      await dossier.create(recursive: true);
    }

    final cible = File(
      '${dossier.path}${Platform.pathSeparator}$_nomFichier',
    );
    // Un téléchargement interrompu laisse un fichier tronqué qui s'installe
    // mal, ou pas du tout. On repart du fichier vide plutôt que de compléter
    // quelque chose dont on ignore l'état.
    if (await cible.exists()) {
      await cible.delete();
    }

    final dio = client ?? Dio();
    await dio.download(
      url,
      cible.path,
      cancelToken: annulation,
      onReceiveProgress: (recu, total) {
        // `total` vaut -1 quand le serveur n'annonce pas de taille. Mieux vaut
        // alors ne rien prétendre que d'inventer un pourcentage : l'écran sait
        // afficher une progression indéterminée.
        if (total > 0) progression(recu / total);
      },
    );

    final taille = await cible.length();
    if (taille == 0) {
      throw StateError('le fichier telecharge est vide');
    }
    return cible;
  }

  /// Ouvre l'installateur du système sur [apk].
  static Future<ResultatInstallation> installer(File apk) async {
    try {
      final ouvert = await canal.invokeMethod<bool>(
        'installer',
        {'chemin': apk.path},
      );
      return ouvert == true
          ? ResultatInstallation.ouvert
          : ResultatInstallation.autorisationDemandee;
    } on PlatformException catch (e) {
      debugPrint('[Maj] Installation refusée : ${e.code} — ${e.message}');
      return ResultatInstallation.impossible;
    } on MissingPluginException {
      // Ni Android, ni banc de test : il n'y a pas d'installateur à appeler.
      return ResultatInstallation.impossible;
    }
  }

  /// L'utilisateur a-t-il déjà autorisé cette application à installer ?
  ///
  /// Sert à choisir le libellé du bouton, pas à décider : l'autorisation se
  /// demande au moment de s'en servir, quand la raison en est visible.
  static Future<bool> autorisationAccordee() async {
    try {
      return await canal.invokeMethod<bool>('peutInstaller') ?? false;
    } catch (_) {
      return false;
    }
  }
}
