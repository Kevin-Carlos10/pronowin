import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'apk_par_abi.dart';
import 'remote_config_service.dart';
import '../config/bookmaker_affiliation.dart';
import '../router/navigation_keys.dart';
import '../widgets/ecran_mise_a_jour.dart';

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
  static Future<void> check({
    required bool estStore,
    required Dio dio,
  }) async {
    try {
      final pkg = await PackageInfo.fromPlatform();

      // La maintenance vaut pour les deux canaux et prime sur tout le reste.
      if (RemoteConfigService.maintenanceMode) {
        await _afficher(
          message:  RemoteConfigService.maintenanceMsg,
          bloquant: true,
          titre:    'Maintenance en cours',
          lien:     null,
          installationDirecte: false);
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

      final verdict = decider(
        courante: pkg.version,
        min:      seuils.min,
        latest:   seuils.latest,
        force:    seuils.force);
      final obligatoire = verdict.obligatoire;
      if (!obligatoire && !verdict.disponible) return;

      // Une mise à jour facultative ne se rappelle qu'une fois par version :
      // la redemander à chaque lancement finit par apprendre à l'utilisateur
      // à fermer la fenêtre sans la lire.
      if (!obligatoire && await _dejaIgnoree(seuils.latest)) return;

      final reponse = await _afficher(
        message:  seuils.message,
        bloquant: obligatoire,
        lien:     seuils.lien,
        // Le canal direct telecharge et installe lui-meme. Le paquet des
        // boutiques ne le peut pas : installer un APK hors Play est reserve
        // aux boutiques d'applications, et cette variante ne declare meme pas
        // la permission.
        installationDirecte: !estStore);

      if (!obligatoire && reponse == ReponseMaj.plusTard) {
        await _memoriserIgnoree(seuils.latest);
      }
    } catch (e, pile) {
      // Le contrôle de version ne doit jamais empêcher l'application de
      // démarrer : tout ce qui échoue ici est rattrapé. Mais « rattrapé » ne
      // veut pas dire « invisible » : ce `catch` vide a avalé pendant des mois
      // l'échec décrit sous `_contexteNavigable`, sans laisser la moindre
      // trace — ni à l'écran, ni dans les journaux. C'est ce silence, et non
      // le défaut lui-même, qui l'a rendu introuvable.
      debugPrint('[Version] contrôle interrompu : $e');
      assert(() {
        debugPrintStack(stackTrace: pile, label: '[Version]');
        return true;
      }());
    }
  }

  /// Faut-il bloquer, proposer, ou se taire.
  ///
  /// `force` ne bloque que s'il existe une version vers laquelle aller.
  /// Auparavant il bloquait seul : activé alors que tout le monde était déjà
  /// à jour, il enfermait l'ensemble des utilisateurs derrière une fenêtre
  /// sans issue, dont l'unique bouton retéléchargeait la version déjà
  /// installée. Relancer l'application ne changeait rien — la condition ne
  /// dépendait pas de la version installée, donc aucune installation ne
  /// pouvait la lever.
  ///
  /// C'est le pendant applicatif du contrôle serveur qui refuse
  /// `MIN > LATEST` : la même erreur, par l'autre porte. Le serveur ne pouvait
  /// pas l'attraper, `force` étant un booléen que rien ne contredit.
  @visibleForTesting
  static ({bool obligatoire, bool disponible}) decider({
    required String courante,
    required String min,
    required String latest,
    required bool force,
  }) {
    final v = _parse(courante);
    final disponible = _comparer(v, _parse(latest)) < 0;
    return (
      obligatoire: _comparer(v, _parse(min)) < 0 || (force && disponible),
      disponible:  disponible,
    );
  }

  /// Seuils du canal direct, lus sur l'API publique.
  ///
  /// Cette requete sert aussi a renseigner le partenariat bookmaker : `/config`
  /// le publie desormais, et l'appeler une seconde fois pour le seul lien
  /// d'affiliation serait une requete de plus au demarrage, sur des reseaux ou
  /// chacune se paie.
  static Future<_Seuils?> _seuilsDirects(Dio dio) async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/config');
      final d = r.data;
      if (d == null) return null;

      // Sans lien configure, l'application n'affiche aucune invitation a
      // parier — plutot qu'un lien mort qui fait cliquer sans rien rapporter.
      BookmakerAffiliation.configurer(d);

      return _Seuils(
        min:     (d['apkMinVersion']    as String?) ?? '1.0.0',
        latest:  (d['apkLatestVersion'] as String?) ?? '1.0.0',
        force:   (d['apkForceUpdate']   as bool?)   ?? false,
        message: (d['updateMessage']    as String?) ??
            'Une nouvelle version de PronoWin est disponible.',
        // L'APK de l'architecture du téléphone, l'universel à défaut (M3).
        lien:    lienApkPour(
          universel: d['apkUrl'] as String?,
          parAbi:    d['apkUrls'],
          abi:       abiAndroid(),
        ),
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

  /// La fenêtre de mise à jour, exposée pour être éprouvée.
  ///
  /// `check()` n'est pas testable directement : il lit Firebase Remote Config
  /// avant toute chose, et l'accès échoue hors application — la fonction
  /// entière étant gardée par un `catch`, le test ne verrait jamais la fenêtre
  /// et passerait sans rien vérifier.
  ///
  /// Ce qui doit être prouvé tient de toute façon à la fenêtre : une mise à
  /// jour obligatoire ne se referme sur aucun geste, une facultative se ferme
  /// sur les deux. Même couture explicite que `fabriqueDioRafraichissement`
  /// dans `dio_client.dart`, pour la même raison.
  @visibleForTesting
  static Future<void> afficherPourTest(
    BuildContext context, {
    required String message,
    required bool bloquant,
    String? lien,
    String? titre,
    bool installationDirecte = false,
  }) => _afficher(contexte: context,
        message: message, bloquant: bloquant, lien: lien, titre: titre,
        installationDirecte: installationDirecte);

  // ─── Boîte de dialogue ─────────────────────────────────────────────────

  /// Ouvre la fenêtre depuis le navigateur racine.
  ///
  /// Le contexte n'est pas un paramètre de `check()`, et c'est le fond du
  /// correctif. `check()` recevait auparavant le `BuildContext` de l'État qui
  /// l'appelle, dans `main.dart`. Or cet État **construit** le
  /// `MaterialApp.router` : son contexte se situe au-dessus de lui, donc
  /// au-dessus de tout `Navigator` et de toute `MaterialLocalizations`.
  /// `showDialog` remonte l'arbre, ne trouve rien, et lève — droit dans le
  /// `catch` de `check()`, qui était vide.
  ///
  /// Aucune fenêtre de mise à jour ne s'est donc jamais affichée, sur aucun
  /// canal, pas plus que l'avis de maintenance. Tout le reste du mécanisme
  /// était juste — seuils, comparaison sémantique, verrouillage, mémoire des
  /// refus — et ne pouvait aboutir à rien.
  ///
  /// Résoudre la clé ici plutôt que de recevoir un contexte rend l'erreur
  /// impossible à refaire : il n'y a plus de mauvais contexte à passer.
  /// `contexte` n'existe que pour les tests, qui montent leur propre arbre.
  /// `FCMService._navigate` procède de même, pour la même raison.
  static Future<ReponseMaj?> _afficher({
    required String message,
    required bool bloquant,
    required String? lien,
    required bool installationDirecte,
    String? titre,
    BuildContext? contexte,
  }) {
    final ctx = contexte ?? rootNavigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('[Version] aucun navigateur monté — écran non affiché');
      return Future<ReponseMaj?>.value(null);
    }

    // Une route opaque, pas une `AlertDialog`.
    //
    // Le rectangle de deux cents pixels annonçait le remplacement de
    // l'application et renvoyait vers le navigateur sans rien dire de plus.
    // L'écran occupe désormais toute la surface, télécharge lui-même et montre
    // son avancement — ce que seule une page peut faire.
    //
    // `barrierDismissible` n'existe pas sur une route opaque : il n'y a plus
    // de barrière à toucher. Le verrouillage tient au `PopScope` de l'écran,
    // qui refuse aussi le retour pendant le téléchargement.
    return Navigator.of(ctx, rootNavigator: true).push<ReponseMaj>(
      PageRouteBuilder<ReponseMaj>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 240),
        transitionsBuilder: (_, animation, _, enfant) =>
            FadeTransition(opacity: animation, child: enfant),
        pageBuilder: (_, _, _) => EcranMiseAJour(
          message:  message,
          bloquant: bloquant,
          lien:     lien,
          titre:    titre,
          installationDirecte: installationDirecte,
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
