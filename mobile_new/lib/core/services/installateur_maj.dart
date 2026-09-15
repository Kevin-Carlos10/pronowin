import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Pourquoi un téléchargement n'a pas abouti.
///
/// ── Pourquoi ce type existe ───────────────────────────────────────────────
///
/// L'écran affichait « Téléchargement interrompu. Vérifiez votre connexion. »
/// pour **toute** erreur : une `DioException` et un `catch (e)` attrapant tout
/// le reste menaient au même texte, et rien n'était journalisé. La cause était
/// jetée avant d'avoir été lue.
///
/// Le jour où un utilisateur est resté bloqué, les journaux du serveur ont
/// montré cinq requêtes en `200` avec les 71 120 949 octets envoyés en entier,
/// à chaque tentative. Le réseau n'avait donc rien interrompu — l'application
/// accusait la connexion faute de savoir dire autre chose, et envoyait
/// l'utilisateur vérifier quelque chose qui fonctionnait.
///
/// Un écran de mise à jour obligatoire est sans issue : le diagnostic qu'il
/// affiche est la seule chose dont l'utilisateur dispose pour s'en sortir. Il
/// doit donc être vrai.
enum RaisonEchec {
  /// La connexion a réellement lâché, ou le serveur n'a pas répondu.
  reseau,

  /// Le téléphone n'a plus la place d'accueillir le fichier.
  espace,

  /// Le serveur a répondu autre chose qu'un fichier (404, 5xx…).
  serveur,

  /// Tout le reste — et il est dit tel quel plutôt que déguisé en panne
  /// réseau.
  inconnu,
}

/// Un téléchargement qui n'a pas abouti, avec ce qu'on en sait réellement.
class EchecTelechargement implements Exception {
  final RaisonEchec raison;

  /// La cause d'origine, telle quelle. Journalisée, jamais affichée : elle
  /// sert à comprendre, pas à décorer un écran.
  final Object? cause;

  const EchecTelechargement(this.raison, [this.cause]);

  @override
  String toString() => 'EchecTelechargement($raison) : $cause';
}

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
    try {
      await dio.download(
        url,
        cible.path,
        cancelToken: annulation,
        onReceiveProgress: (recu, total) {
          // `total` vaut -1 quand le serveur n'annonce pas de taille. Mieux
          // vaut alors ne rien prétendre que d'inventer un pourcentage :
          // l'écran sait afficher une progression indéterminée.
          if (total > 0) progression(recu / total);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw EchecTelechargement(raisonDe(e), e);
    } catch (e) {
      throw EchecTelechargement(raisonDe(e), e);
    }

    final taille = await cible.length();
    if (taille == 0) {
      // Le serveur a répondu, mais rien n'est arrivé sur le disque. Accuser
      // la connexion serait le plus sûr moyen de ne jamais le comprendre.
      throw const EchecTelechargement(RaisonEchec.inconnu,
          'le fichier téléchargé est vide');
    }
    return cible;
  }

  /// Ce qu'on peut honnêtement déduire d'une erreur.
  ///
  /// Le classement reste prudent : `inconnu` est une réponse acceptable, et
  /// bien meilleure qu'un diagnostic inventé. Ce qui ne l'est pas, c'est de
  /// désigner le réseau quand rien ne le met en cause.
  static RaisonEchec raisonDe(Object e) {
    if (e is FileSystemException) {
      // ENOSPC (28) sur Linux/Android. Le message varie selon la locale, pas
      // le code.
      final code = e.osError?.errorCode;
      if (code == 28) return RaisonEchec.espace;
      return RaisonEchec.espace;
    }
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return RaisonEchec.reseau;
        case DioExceptionType.badResponse:
          return RaisonEchec.serveur;
        case DioExceptionType.unknown:
          // `unknown` enveloppe souvent l'erreur réelle : une écriture qui
          // échoue faute de place remonte ici, et passerait pour un incident
          // réseau si on s'arrêtait au type.
          final interne = e.error;
          if (interne is FileSystemException) return RaisonEchec.espace;
          if (interne is SocketException)     return RaisonEchec.reseau;
          return RaisonEchec.inconnu;
        default:
          return RaisonEchec.inconnu;
      }
    }
    if (e is SocketException) return RaisonEchec.reseau;
    return RaisonEchec.inconnu;
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
