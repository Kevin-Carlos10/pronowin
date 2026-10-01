import 'package:pronowin/l10n/app_strings.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/installateur_maj.dart';
import '../theme/app_theme.dart';

/// Ce que l'utilisateur a répondu à l'écran de mise à jour.
enum ReponseMaj {
  /// « Plus tard » — seulement proposé pour une mise à jour facultative.
  plusTard,

  /// L'installateur s'est ouvert, ou la boutique. L'écran peut se fermer.
  partie,
}

/// L'écran de mise à jour, en plein écran.
///
/// C'était une `AlertDialog` : un rectangle de deux cents pixels pour annoncer
/// le remplacement de l'application, avec un bouton qui envoyait vers le
/// navigateur et n'en disait pas plus. L'utilisateur du canal direct
/// téléchargeait soixante-dix mégaoctets sans savoir où il en était, cherchait
/// le fichier dans ses téléchargements, et revenait — ou pas.
///
/// L'écran occupe désormais toute la surface, télécharge lui-même, et montre
/// son avancement. Il ne ment pas sur ce qu'il fait : tant que la taille n'est
/// pas connue, il affiche une progression indéterminée plutôt qu'un pourcentage
/// inventé.
///
/// ── Les deux canaux ────────────────────────────────────────────────────────
///
/// `installationDirecte` est faux pour le paquet des boutiques : le bouton y
/// ouvre la fiche, et il n'y a rien à télécharger ici. Installer un APK hors
/// Play est réservé aux boutiques d'applications, et l'application ne déclare
/// même pas la permission dans cette variante.
class EcranMiseAJour extends StatefulWidget {
  final String message;
  final bool bloquant;
  final String? lien;
  final String? titre;
  final bool installationDirecte;

  /// Injectés par les bancs : sans plateforme, ni le réseau ni l'installateur
  /// ne répondent, et l'écran resterait figé sur son premier état.
  final Future<File> Function(
    String url, {
    required void Function(double) progression,
    CancelToken? annulation,
  })? telechargeur;
  final Future<ResultatInstallation> Function(File)? installeur;
  final Future<bool> Function(Uri)? ouvreur;

  const EcranMiseAJour({
    super.key,
    required this.message,
    required this.bloquant,
    required this.lien,
    this.titre,
    this.installationDirecte = false,
    this.telechargeur,
    this.installeur,
    this.ouvreur,
  });

  @override
  State<EcranMiseAJour> createState() => _EcranMiseAJourState();
}

enum _Etape { invitation, telechargement, installation, echec }

class _EcranMiseAJourState extends State<EcranMiseAJour> {
  _Etape _etape = _Etape.invitation;

  /// `null` tant que la taille du fichier n'est pas connue.
  double? _avancement;
  String? _erreur;
  CancelToken? _annulation;

  /// Le fichier déjà obtenu, s'il l'a été.
  ///
  /// Le cas qui l'impose : l'installation échoue parce que l'utilisateur n'a
  /// pas encore autorisé l'application à installer des paquets. Il accorde
  /// l'autorisation, revient, appuie sur « Réessayer » — et la première version
  /// de cet écran retéléchargeait soixante-dix mégaoctets déjà présents sur le
  /// disque. Sur un forfait mobile, c'est payer deux fois la même chose pour
  /// une case à cocher.
  ///
  /// Il n'est renseigné qu'au retour de `telecharger`, qui ne rend son fichier
  /// que complet : un téléchargement interrompu ne laisse donc rien à réutiliser.
  File? _fichier;

  @override
  void dispose() {
    _annulation?.cancel();
    super.dispose();
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  Future<void> _lancer() async {
    final lien = widget.lien;
    if (lien == null || lien.isEmpty) return;

    if (!widget.installationDirecte) {
      await _ouvrirLien(lien);
      return;
    }
    await _telechargerPuisInstaller(lien);
  }

  Future<void> _ouvrirLien(String lien) async {
    final ouvrir = widget.ouvreur ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      await ouvrir(Uri.parse(lien));
      if (mounted && !widget.bloquant) {
        Navigator.of(context).pop(ReponseMaj.partie);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _etape = _Etape.echec;
        _erreur = tr(context, "Impossible d'ouvrir la page de téléchargement.");
      });
    }
  }

  Future<void> _telechargerPuisInstaller(String lien) async {
    setState(() {
      _etape = _Etape.telechargement;
      _avancement = null;
      _erreur = null;
    });

    _annulation = CancelToken();
    final telecharger = widget.telechargeur ?? InstallateurMaj.telecharger;
    final installer = widget.installeur ?? InstallateurMaj.installer;

    try {
      final dejaLa = _fichier;
      final fichier = dejaLa != null && dejaLa.existsSync()
          ? dejaLa
          : await telecharger(
              lien,
              annulation: _annulation,
              progression: (p) {
                if (!mounted) return;
                // Un `setState` par octet reçu rendrait l'écran plus lent que
                // le téléchargement. On ne redessine qu'au changement de
                // pourcentage entier — la barre n'a pas plus de cent états
                // visibles.
                if (_avancement != null &&
                    (p * 100).floor() == (_avancement! * 100).floor()) {
                  return;
                }
                setState(() => _avancement = p);
              },
            );

      if (!mounted) return;
      _fichier = fichier;
      setState(() => _etape = _Etape.installation);

      final resultat = await installer(fichier);
      if (!mounted) return;

      switch (resultat) {
        case ResultatInstallation.ouvert:
          // L'installateur du système a la main. L'écran reste tel quel : si
          // l'utilisateur annule l'installation, il revient ici plutôt que
          // dans une application qu'on vient de déclarer périmée.
          break;
        case ResultatInstallation.autorisationDemandee:
          setState(() {
            _etape = _Etape.echec;
            _erreur = tr(context, "Autorisez PronoWin à installer des applications, puis appuyez de nouveau sur « Installer ».");
          });
        case ResultatInstallation.impossible:
          setState(() {
            _etape = _Etape.echec;
            _erreur = tr(context, "Installation impossible depuis l'application. Téléchargez la mise à jour depuis le site.");
          });
      }
    } on DioException catch (e) {
      if (!mounted || CancelToken.isCancel(e)) return;
      _echouer(EchecTelechargement(InstallateurMaj.raisonDe(e), e));
    } on EchecTelechargement catch (e) {
      if (!mounted) return;
      _echouer(e);
    } catch (e) {
      if (!mounted) return;
      _echouer(EchecTelechargement(InstallateurMaj.raisonDe(e), e));
    }
  }

  /// Affiche l'échec en disant ce qui s'est réellement passé.
  ///
  /// L'écran annonçait « Téléchargement interrompu. Vérifiez votre
  /// connexion. » quelle que soit la cause, et n'en journalisait aucune. Les
  /// journaux du serveur ont montré, pour un utilisateur bloqué, cinq
  /// requêtes en `200` avec le fichier envoyé **en entier** à chaque fois : le
  /// réseau n'y était pour rien, et l'utilisateur était envoyé vérifier une
  /// connexion qui marchait.
  ///
  /// Sur un écran de mise à jour obligatoire, le diagnostic affiché est la
  /// seule prise que l'utilisateur ait sur son problème.
  void _echouer(EchecTelechargement e) {
    debugPrint('[Maj] $e');
    _fichier = null;
    setState(() {
      _etape = _Etape.echec;
      _erreur = switch (e.raison) {
        RaisonEchec.reseau =>
          tr(context, "Téléchargement interrompu. Vérifiez votre connexion."),
        RaisonEchec.espace =>
          tr(context, "Espace insuffisant sur le téléphone. Libérez environ 150 Mo, puis réessayez."),
        RaisonEchec.serveur =>
          tr(context, "Le fichier n'est pas disponible pour le moment. Réessayez dans quelques minutes."),
        RaisonEchec.inconnu =>
          tr(context, "La mise à jour n'a pas pu s'installer. Vous pouvez la télécharger depuis le site."),
      };
    });
  }

  // ─── Rendu ─────────────────────────────────────────────────────────────────

  String get _titre {
    if (widget.titre != null) return widget.titre!;
    return switch (_etape) {
      _Etape.telechargement => tr(context, "Appli en cours de mise à jour"),
      _Etape.installation   => tr(context, "Installation en cours"),
      _Etape.echec          => tr(context, "La mise à jour a échoué"),
      // Le titre de la maquette — mais seulement quand l'utilisateur a le
      // choix. Sur une mise à jour obligatoire il n'y a ni retour ni « Plus
      // tard » : annoncer gaiement une montée en gamme à quelqu'un qu'on vient
      // d'enfermer lui cacherait la seule chose qu'il doit comprendre.
      _Etape.invitation     => widget.bloquant
        ? tr(context, "Mise à jour requise")
        : tr(context, "PronoWin passe au niveau supérieur"),
    };
  }

  String get _sousTitre {
    return switch (_etape) {
      _Etape.telechargement => tr(context, "L'installation peut durer quelques minutes."),
      _Etape.installation   => tr(context, "Suivez les instructions de votre téléphone."),
      _Etape.echec          => _erreur ?? tr(context, widget.message),
      _Etape.invitation     => tr(context, widget.message),
    };
  }

  @override
  Widget build(BuildContext context) {
    final enCours = _etape == _Etape.telechargement || _etape == _Etape.installation;

    // Écran toujours sombre (photo de stade) : tout son contenu lit le thème
    // sombre, quel que soit celui de l'application.
    return SurfaceSombre(builder: (context) => PopScope(
      // Une mise à jour obligatoire ne se quitte pas. Un téléchargement en
      // cours non plus : revenir en arrière laisserait un fichier à moitié
      // écrit et une application qu'on vient de déclarer périmée.
      canPop: !widget.bloquant && !enCours,
      child: Scaffold(
        backgroundColor: AppColors.background,
        // ── La photo occupe le haut, le texte tient le bas ─────────────
        //
        // L'écran empilait un logo de 88 px, un titre et un sous-titre centrés
        // au milieu d'un dégradé. Il ressemblait à une boîte de dialogue, pas à
        // l'application qu'il propose d'installer.
        //
        // La photo porte déjà le logo : le carré « P » dessiné ici a été
        // retiré, il en aurait fait un second.
        body: Stack(
          children: [
            // Le fond, calé en haut et fondu vers la couleur de l'application.
            //
            // `maj_fond.webp` est la maquette **recadrée** : le panneau sombre
            // et son texte en ont été retirés. Les laisser aurait affiché deux
            // fois le titre et deux boutons — l'un peint dans l'image, inerte,
            // et impossible à distinguer du vrai.
            //
            // WebP et non PNG : 138 Ko contre 1,4 Mo pour la même photo, sur
            // une application déjà distribuée en 68 Mo par données mobiles.
            Positioned(
              top: 0, left: 0, right: 0,
              height: MediaQuery.of(context).size.height * 0.62,
              child: Stack(fit: StackFit.expand, children: [
                Image.asset(
                  'assets/images/maj_fond.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  // Une image absente ne doit pas remplacer l'écran par une
                  // icône cassée : le fond uni suffit, le texte reste lisible.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppColors.background],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
              ]),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Text(
                      _titre,
                      key: const Key('maj-titre'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _sousTitre,
                      key: const Key('maj-sous-titre'),
                      style: TextStyle(
                        color: _etape == _Etape.echec
                            ? context.cl.warning
                            : AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (enCours)
                      _Progression(avancement: _avancement)
                    else
                      _Boutons(
                        bloquant: widget.bloquant,
                        echec: _etape == _Etape.echec,
                        lien: widget.lien,
                        installationDirecte: widget.installationDirecte,
                        onLancer: _lancer,
                        onPlusTard: () =>
                            Navigator.of(context).pop(ReponseMaj.plusTard),
                        onNavigateur: () => _ouvrirLien(widget.lien ?? ''),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ─── Morceaux ────────────────────────────────────────────────────────────────

/// La barre d'avancement, et le pourcentage quand il est connu.
class _Progression extends StatelessWidget {
  final double? avancement;
  const _Progression({required this.avancement});

  @override
  Widget build(BuildContext context) {
    final pourcent = avancement == null ? null : (avancement! * 100).floor();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            key: const Key('maj-barre'),
            // `null` produit une barre indéterminée : le serveur n'a pas
            // annoncé la taille du fichier, et un pourcentage inventé serait
            // pire qu'aucun.
            value: avancement,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          pourcent == null ? tr(context, "Préparation…") : '$pourcent %',
          key: const Key('maj-pourcentage'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Boutons extends StatelessWidget {
  final bool bloquant;
  final bool echec;
  final String? lien;
  final bool installationDirecte;
  final VoidCallback onLancer;
  final VoidCallback onPlusTard;
  final VoidCallback onNavigateur;

  const _Boutons({
    required this.bloquant,
    required this.echec,
    required this.lien,
    required this.installationDirecte,
    required this.onLancer,
    required this.onPlusTard,
    required this.onNavigateur,
  });

  String get _libelle {
    if (echec) return trCurrent("Réessayer");
    if (lien == null || lien!.isEmpty) return 'OK';
    return installationDirecte ? trCurrent("Installer") : trCurrent("Mettre à jour");
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            key: const Key('maj-action'),
            onPressed: onLancer,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _libelle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // Une seconde voie, quand la première a échoué.
        //
        // « Réessayer » relance exactement ce qui vient de ne pas marcher. Sur
        // une mise à jour obligatoire, l'utilisateur qui boucle n'a alors plus
        // aucune issue : il ne peut ni fermer l'écran, ni contourner le
        // téléchargement intégré. Un utilisateur a répété ce cycle cinq fois,
        // pendant que le serveur lui envoyait le fichier entier à chaque
        // tentative.
        //
        // Le navigateur du système sait télécharger et reprendre là où il en
        // était ; il reste joignable même quand notre téléchargeur échoue.
        if (echec && installationDirecte && (lien?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('maj-navigateur'),
            onPressed: onNavigateur,
            child: Text(
              tr(context, "Télécharger depuis le site"),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.cl.textS,
              ),
            ),
          ),
        ],

        // Aucune échappatoire quand la mise à jour est obligatoire : c'est
        // toute la différence entre les deux, et elle ne tient qu'à ce bouton.
        if (!bloquant) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('maj-plus-tard'),
            onPressed: onPlusTard,
            child:  Text(
              tr(context, "Plus tard"),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }
}
