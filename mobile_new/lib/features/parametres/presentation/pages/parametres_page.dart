import '../widgets/sessions_sheet.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../../../core/config/contact_support.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/logo_marque.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../compte/presentation/pages/compte_page.dart' show rafraichirDonneesCompte, confirmerDeconnexion;
import '../providers/settings_provider.dart';
import '../providers/security_provider.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../core/config/pages_legales.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../../../shared/utils/messages.dart';
import 'package:pronowin/core/config/sans_pari.dart';
import '../../../../core/services/cache_fichiers.dart';
import '../widgets/apercu_technique.dart';
import '../widgets/notifications_telephone.dart';
import '../../../../core/router/onglet_demarrage.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/services/version_service.dart';
import '../widgets/reglages_ui.dart';
import 'reglages_sous_pages.dart';

/// Entrées animées à la première visite seulement (motion.dart).
double? get _apparitionParametres => PremiereApparition.valeur('paramètres');

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/compte';


/// L'année du copyright était figée à 2026 dans deux textes distincts.
final _copyrightYear = DateTime.now().year;

/// La place occupée par les fichiers temporaires (`cache_fichiers.dart`).
final _tailleCacheProvider = FutureProvider.autoDispose<int>((ref) => CacheFichiers.taille());

/// Un compte est-il connecté ? Pour « Se déconnecter ». Si l'authentification
/// ne peut pas démarrer, la page s'affiche quand même, sans cette ligne.
final _connecteProvider = Provider.autoDispose<bool>((ref) {
  try {
    return ref.watch(authProvider) is AuthAuthenticated;
  } catch (_) {
    return false;
  }
});

/// L'état de la version installée, pour la carte du bas.
final _etatVersionProvider = FutureProvider.autoDispose<EtatVersion?>((ref) =>
    VersionService.etat(estStore: ref.read(isStoreBuildProvider), dio: ref.read(dioProvider)));

/// Les Paramètres, au dessin de l'application 1xPartners (demande du
/// 11 novembre 2026) : la sécurité d'abord, puis les réglages de
/// l'application, chacun sur une ligne — les notifications et les listes de
/// choix ont leur sous-page (`reglages_sous_pages.dart`) —, et la version
/// installée dans une carte en bas.
class ParametresPage extends ConsumerWidget {
  const ParametresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings     = ref.watch(settingsProvider);
    final bioAvailable = ref.watch(bioAvailableProvider);
    final appVersion   = ref.watch(appVersionProvider).value ?? '';
    // La place occupée par le cache, comme 1xBet (7 novembre 2026).
    final tailleCache  = ref.watch(_tailleCacheProvider).valueOrNull;
    final notifsActives = [settings.notifMatch, settings.notifPromo,
        settings.notifReferral, settings.notifPremium].where((v) => v).length;
    // Protégée : un code PIN, ou la biométrie là où l'appareil l'offre.
    final protege = settings.pinEnabled
        || (settings.bioEnabled && (bioAvailable.valueOrNull ?? false));
    final connecte = ref.watch(_connecteProvider);

    StatutReglage statut(bool actif) => StatutReglage(
      actif: actif, texte: actif ? tr(context, "Activé") : tr(context, "Pas activé"));

    // Les sections entrent l'une après l'autre, à la première visite.
    var rang = 0;
    Widget section(String titre, List<Widget> lignes) {
      final i = rang++;
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EnTeteReglages(titre),
          CarteReglages(lignes),
        ]),
      ).animate(delay: (40 + 40 * i).ms, value: _apparitionParametres)
        .fadeIn(duration: 280.ms).slideY(begin: 0.03, end: 0, curve: Curves.easeOutCubic);
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => retourOuAller(context, repli: _repli),
        ),
        title: Text(tr(context, "Paramètres"),
          style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(margeEcran, 14, margeEcran, 60),
        children: [

          // ─── SÉCURITÉ ─────────────────────────────────────────────────
          section(tr(context, "Sécurité"), [
            LigneReglage(
              key: const Key('reglage-protection'),
              icone: Icons.shield_outlined,
              titre: tr(context, "Protection de l'application"),
              statut: protege
                  ? StatutReglage(actif: true, texte: tr(context, "Renforcée"))
                  : StatutReglage.avertissement(tr(context, "Faible : active le code PIN ou la biométrie")),
              onTap: null,
            ),
            LigneInterrupteur(
              key: const Key('reglage-pin'),
              icone: Icons.lock_outline_rounded,
              titre: tr(context, "Code PIN"),
              statut: statut(settings.pinEnabled),
              valeur: settings.pinEnabled,
              onChanged: (v) async {
                if (v) {
                  await context.push('/parametres/pin');
                } else {
                  _showDisablePinSheet(context, ref);
                }
              },
            ),
            bioAvailable.when(
              data: (available) => LigneInterrupteur(
                key: const Key('reglage-biometrie'),
                icone: Icons.fingerprint_rounded,
                titre: tr(context, "Déverrouillage biométrique"),
                statut: available
                    ? statut(settings.bioEnabled)
                    : StatutReglage(actif: false, texte: tr(context, "Non disponible sur cet appareil")),
                valeur: settings.bioEnabled && available,
                indisponible: !available,
                onChanged: available ? (v) async {
                  if (v) {
                    final auth = LocalAuthentication();
                    try {
                      final ok = await auth.authenticate(
                        localizedReason: tr(context, "Confirmez pour activer la biométrie"),
                        options: const AuthenticationOptions(
                          biometricOnly: false, stickyAuth: true),
                      );
                      if (ok) {
                        await ref.read(settingsProvider.notifier).setBioEnabled(true);
                        if (context.mounted) {
                          afficherMessage(context, tr(context, "Biométrie activée"), type: TypeMessage.succes);
                        }
                      }
                    } catch (e) {
                      debugPrint('[Bio] Activation refusée : $e');
                      if (context.mounted) {
                        afficherMessage(context, messageErreurBio(e), type: TypeMessage.erreur);
                      }
                    }
                  } else {
                    await ref.read(settingsProvider.notifier).setBioEnabled(false);
                  }
                } : null,
              ),
              loading: () => LigneInterrupteur(
                icone: Icons.fingerprint_rounded,
                titre: tr(context, "Déverrouillage biométrique"),
                sousTitre: tr(context, "Vérification en cours..."),
                valeur: false, onChanged: null,
              ),
              error: (_, _) => LigneInterrupteur(
                icone: Icons.fingerprint_rounded,
                titre: tr(context, "Déverrouillage biométrique"),
                statut: StatutReglage(actif: false, texte: tr(context, "Non disponible sur cet appareil")),
                valeur: false, onChanged: null, indisponible: true,
              ),
            ),
            if (settings.pinEnabled)
              LigneReglage(
                icone: Icons.password_rounded,
                titre: tr(context, "Changer le code PIN"),
                onTap: () => context.push('/parametres/pin'),
              ),
            LigneReglage(
              icone: Icons.devices_outlined,
              titre: tr(context, "Appareils connectés"),
              onTap: () => _showSessionsSheet(context),
            ),
          ]),

          // ─── PARAMÈTRES DE L'APPLICATION ──────────────────────────────
          section(tr(context, "Paramètres de l'application"), [
            LigneReglage(
              key: const Key('reglage-notifications'),
              icone: Icons.notifications_none_rounded,
              titre: tr(context, "Notifications push"),
              statut: settings.notifPause
                  ? StatutReglage(actif: false, texte: tr(context, "En pause"))
                  : StatutReglage(
                      actif: notifsActives > 0,
                      texte: notifsActives == 4 ? tr(context, "Activé")
                          : notifsActives == 0 ? tr(context, "Pas activé")
                          : tr(context, "{arg0} sur 4 activées", [notifsActives])),
              onTap: () => ouvrirSousPage(context, const NotificationsReglagesPage()),
            ),
            LigneReglage(
              key: const Key('reglage-theme'),
              icone: Icons.dark_mode_outlined,
              titre: tr(context, "Thème"), sousTitre: settings.themeName,
              onTap: () => ouvrirChoixTheme(context, ref),
            ),
            LigneReglage(
              key: const Key('reglage-langue'),
              icone: Icons.language_outlined,
              titre: tr(context, "Langue"), sousTitre: settings.langName,
              onTap: () => ouvrirChoixLangue(context, ref),
            ),
            // L'« Onglet principal » de Sofascore (8 novembre 2026).
            LigneReglage(
              key: const Key('reglage-onglet'),
              icone: Icons.space_dashboard_outlined,
              titre: tr(context, "Onglet d'ouverture"),
              sousTitre: libelleOnglet(context, ref.watch(ongletDemarrageProvider)),
              onTap: () => ouvrirChoixOnglet(context, ref),
            ),
            LigneReglage(
              icone: Icons.cleaning_services_outlined,
              titre: tr(context, "Vider le cache"),
              sousTitre: tailleCache == null ? null
                  : CacheFichiers.lisible(tailleCache, langue: AppStrings.of(context).locale.languageCode),
              onTap: () => _showClearCacheSheet(context, ref),
            ),
          ]),

          // ─── MON COMPTE ───────────────────────────────────────────────
          section(tr(context, "Mon compte"), [
            LigneReglage(
              icone: Icons.person_outline_rounded,
              titre: tr(context, "Modifier le profil"),
              onTap: () => context.push('/compte/edit'),
            ),
            LigneReglage(
              icone: Icons.block_outlined,
              titre: tr(context, "Membres bloqués"),
              onTap: () => context.push('/parametres/bloques'),
            ),
            if (connecte)
              LigneReglage(
                key: const Key('reglage-deconnexion'),
                icone: Icons.logout_rounded,
                titre: tr(context, "Se déconnecter"),
                danger: true,
                onTap: () => confirmerDeconnexion(context, ref),
              ),
          ]),

          // ─── AIDE ─────────────────────────────────────────────────────
          // Repris de 1xBet (7 novembre 2026) : revoir la présentation, et
          // copier les informations techniques à joindre au support.
          section(tr(context, "Aide"), [
            LigneReglage(
              icone: Icons.slideshow_outlined,
              titre: tr(context, "Présentation de l'application"),
              onTap: () => context.push('/presentation'),
            ),
            LigneReglage(
              icone: Icons.developer_mode_outlined,
              titre: tr(context, "Aperçu technique"),
              onTap: () => afficherApercuTechnique(context, ref),
            ),
            // Comme Sofascore (8 novembre 2026) : un message et une capture,
            // lus dans l'administration.
            LigneReglage(
              icone: Icons.rate_review_outlined,
              titre: tr(context, "Donne-nous ton avis"),
              onTap: () => context.push('/parametres/avis'),
            ),
          ]),

          // ─── PARTAGER ET SUIVRE ───────────────────────────────────────
          // Noter, partager par lien ou par QR code, suivre les chaînes : ce
          // que 1xBet, Sofascore et FotMob rangent ensemble (11 novembre
          // 2026). La note n'a de sens que pour une version des boutiques.
          section(tr(context, "Partager et suivre"), [
            if (ref.watch(isStoreBuildProvider))
              LigneReglage(
                key: const Key('reglage-noter'),
                icone: Icons.star_outline_rounded,
                titre: tr(context, "Noter l'application"),
                onTap: () => InAppReview.instance
                    .openStoreListing(appStoreId: AppConstants.appStoreId).catchError((_) {}),
              ),
            Builder(builder: (ligne) => LigneReglage(
              icone: Icons.ios_share_outlined,
              titre: tr(context, "Partager l'application"),
              onTap: () => partagerApplication(ligne),
            )),
            LigneReglage(
              key: const Key('reglage-qr'),
              icone: Icons.qr_code_2_rounded,
              titre: tr(context, "Partager via QR code"),
              onTap: () => ouvrirSousPage(context, const PartageQrPage()),
            ),
            LigneReglage(
              key: const Key('reglage-reseaux'),
              icone: Icons.groups_outlined,
              titre: tr(context, "Réseaux sociaux"),
              sousTitre: 'Telegram, WhatsApp, Facebook',
              onTap: () => ouvrirSousPage(context, const ReseauxSociauxPage()),
            ),
          ]),

          // ─── LÉGAL ────────────────────────────────────────────────────
          // Les textes publics vivent sur le site, et l'application y
          // renvoie : ce sont les documents qu'on cite, qu'un examinateur
          // ouvre, et qu'un utilisateur doit pouvoir lire sans l'application.
          // « Jeu responsable » reste embarqué : le site n'en a pas de page,
          // et ces ressources doivent rester atteignables même hors ligne.
          section(tr(context, "Informations légales"), [
            LigneReglage(
              icone: Icons.description_outlined,
              titre: tr(context, "Conditions d'utilisation"),
              onTap: () => PagesLegales.ouvrir(
                context,
                PagesLegales.cgu(estStore: ref.read(isStoreBuildProvider),
                    sansPari: ref.read(sansPariProvider)),
                titre: PagesLegales.titreCgu),
            ),
            LigneReglage(
              icone: Icons.privacy_tip_outlined,
              titre: tr(context, "Politique de confidentialité"),
              onTap: () => PagesLegales.ouvrir(
                context, PagesLegales.confidentialite,
                titre: PagesLegales.titreConfidentialite),
            ),
            // Pas sur iPhone (`sansPariProvider`) : l'application n'y propose
            // rien qui touche au pari, et une page d'aide contre l'addiction au
            // jeu disait le contraire à l'examen.
            if (!ref.watch(sansPariProvider))
              LigneReglage(
                icone: Icons.health_and_safety_outlined,
                titre: tr(context, "Jeu responsable"),
                onTap: () => context.push('/parametres/jeu-responsable'),
              ),
            // Les mentions légales portent l'identité de l'éditeur : elles
            // vivent sur le site, on y renvoie sans les recopier.
            LigneReglage(
              icone: Icons.gavel_outlined,
              titre: tr(context, "Mentions légales"),
              onTap: () => PagesLegales.ouvrir(
                context, PagesLegales.mentionsLegales,
                titre: tr(context, "Mentions légales")),
            ),
            LigneReglage(
              icone: Icons.info_outline_rounded,
              titre: tr(context, "À propos"),
              onTap: () => _showAboutSheet(context, appVersion),
            ),
          ]),

          // ─── VERSION ──────────────────────────────────────────────────
          // « Vous utilisez la dernière version de l'appli », comme
          // 1xPartners ; une mise à jour à installer sinon.
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: _CarteVersion(versionInstallee: appVersion),
          ),

          // ─── ZONE DE DANGER ───────────────────────────────────────────
          // Apple (5.1.1(v)) et Google Play exigent la suppression du compte
          // dès lors qu'on permet d'en créer un.
          section(tr(context, "Zone de danger"), [
            LigneReglage(
              key: const Key('reglage-supprimer-compte'),
              icone: Icons.delete_outline_rounded,
              titre: tr(context, "Supprimer le compte"),
              // Le serveur anonymise : il vide les champs personnels et garde
              // la ligne, l'historique et la bankroll. Le libellé ne promet
              // donc pas davantage.
              sousTitre: tr(context, "Fermer ton compte et effacer tes informations"),
              danger: true,
              onTap: () => _showDeleteAccountSheet(context, ref),
            ),
          ]),

          Center(
            child: Text(
              tr(context, "© {arg0} PronoWin. Tous droits réservés.", [_copyrightYear]),
              style: TextStyle(color: context.cl.textM, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom sheet : désactiver le PIN ────────────────────────────────────────
  void _showDisablePinSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        icon: Icons.lock_reset_rounded,
        iconColor: context.cl.warning,
        title: tr(context, "Désactiver le PIN ?"),
        body: tr(context, "L'application ne sera plus protégée par un code PIN.\nTa sécurité sera réduite."),
        confirmLabel: tr(context, "Désactiver"),
        confirmColor: context.cl.warning,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).setPinEnabled(false);
          if (context.mounted) {
            Navigator.pop(context);
            afficherMessage(context, tr(context, "Code PIN désactivé"));
          }
        },
      ),
    );
  }

  // ─── Bottom sheet : Vider le cache ────────────────────────────────────────────
  void _showClearCacheSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        icon: Icons.storage_rounded,
        iconColor: context.cl.textS,
        title: tr(context, "Vider le cache ?"),
        body: tr(context, "Les données temporaires seront supprimées.\nTes paramètres et ta session seront conservés."),
        confirmLabel: tr(context, "Vider le cache"),
        confirmColor: AppColors.primary,
        onConfirm: () async {
          await ref.read(settingsProvider.notifier).clearCache();
          // Les images téléchargées : l'essentiel de la place occupée.
          await CacheFichiers.vider();
          ref.invalidate(_tailleCacheProvider);
          if (context.mounted) {
            Navigator.pop(context);
            afficherMessage(context, tr(context, "Cache vidé"), type: TypeMessage.succes);
          }
        },
      ),
    );
  }

  void _showSessionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cl.surface,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: const SessionsSheet()),
    );
  }

  // ─── Bottom sheet : À propos ──────────────────────────────────────────────────
  void _showAboutSheet(BuildContext context, String version) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.degradeMarque,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20, offset: const Offset(0, 8))]),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 38),
          ).animate(value: _apparitionParametres).scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          const LogotypePronoWin(taille: 26),
          const SizedBox(height: 6),
          Text(tr(context, "Version {arg0}", [version.replaceFirst('v', '')]),
            style: TextStyle(color: context.cl.textS, fontSize: 13)),
          const SizedBox(height: 4),
          Text(tr(context, "© {arg0} PronoWin. Tous droits réservés.", [_copyrightYear]),
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            _AboutChip(
              icon: Icons.star_rounded, label: tr(context, "Noter l'application"), color: context.cl.warning,
              // Sur iPhone, la fiche App Store exige l'identifiant de l'app :
              // sans lui, le bouton ne faisait rien.
              onTap: () => InAppReview.instance
                  .openStoreListing(appStoreId: AppConstants.appStoreId).catchError((_) {}),
            ),
            _AboutChip(
              icon: Icons.mail_outline_rounded, label: tr(context, "Nous contacter"), color: context.cl.info,
              onTap: () => ContactSupport.ouvrirEmail(),
            ),
            _AboutChip(
              marque: Marque.telegram, label: 'Telegram', color: Marque.telegram.couleur,
              onTap: () => ContactSupport.ouvrirTelegram(),
            ),
            _AboutChip(
              marque: Marque.whatsapp, label: 'WhatsApp', color: Marque.whatsapp.couleur,
              onTap: () => ContactSupport.ouvrirWhatsapp(),
            ),
            _AboutChip(
              icon: Icons.facebook_rounded, label: 'Facebook', color: const Color(0xFF1877F2),
              onTap: () => ContactSupport.ouvrirFacebook(),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cl.textP,
                side: BorderSide(color: context.cl.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child:  Text(tr(context, "Fermer")),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Bottom sheet : Supprimer le compte ───────────────────────────────────────
  void _showDeleteAccountSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteAccountSheet(ref: ref),
    );
  }
}

// ─── _DeleteAccountSheet ──────────────────────────────────────────────────────
class _DeleteAccountSheet extends StatefulWidget {
  final WidgetRef ref;
  const _DeleteAccountSheet({required this.ref});
  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String _input = '';

  bool get _confirmed => _input.trim().toUpperCase() == 'SUPPRIMER';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
    // Défilante : avec le texte agrandi sur un petit écran, la feuille
    // dépassait de 130 px et cachait le bouton de confirmation.
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),

      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: context.cl.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: context.cl.error.withValues(alpha: 0.3), width: 1.5)),
        child: Icon(Icons.delete_forever_rounded, color: context.cl.error, size: 36)),
      const SizedBox(height: 16),

      Text(tr(context, "Supprimer le compte"), style: TextStyle(
        color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      // Annonçait « Toutes tes données, ton historique et ton abonnement
      // seront définitivement supprimés ». Aucune des trois affirmations
      // n'était exacte : le serveur anonymise le compte — il vide les champs
      // personnels, met `isActive` à faux et conserve la ligne, l'historique
      // et la bankroll —, et il ne touche jamais à l'abonnement.
      Text(
        tr(context, "Cette action est irréversible. Tes informations personnelles sont effacées et tu perds l'accès à ton compte."),
        style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 20),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cl.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cl.error.withValues(alpha: 0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // « Ton abonnement Premium sera annulé » était faux, et
          // dangereusement : la suppression ne touche ni `subscriptionPlan`
          // ni `subscriptionExpiresAt`, et aucune résiliation n'est appelée
          // nulle part. En facturation Google Play, seul Google peut résilier.
          //
          // Quelqu'un qui supprime son compte pour cesser de payer continuait
          // donc d'être débité tous les mois, après avoir lu le contraire sur
          // l'écran qui le lui demandait. C'est l'avertissement qui devait le
          // protéger qui causait le prélèvement.
          //
          // Et la boutique est celle du téléphone : l'iPhone affichait « depuis
          // le Play Store » (vidéo du 3 octobre 2026).
          _DeleteWarning(!widget.ref.read(isStoreBuildProvider)
              ? tr(context, "Ton abonnement n'est ni résilié ni remboursé")
              : Platform.isIOS
                ? tr(context, "Ton abonnement n'est pas résilié : fais-le depuis l'App Store (Réglages, puis ton nom, puis Abonnements)")
                : tr(context, "Ton abonnement n'est pas résilié : fais-le depuis le Play Store")),
          const SizedBox(height: 6),
          _DeleteWarning(tr(context, "Tu perds l'accès à tes gains de parrainage")),
          const SizedBox(height: 6),
          // Anonymisé, pas effacé — c'est ce que fait `deleteAccount`. Une
          // information, pas une perte : la croix rouge la rangeait avec ce
          // qu'on perd (vidéo du 5 octobre 2026).
          _DeleteWarning(tr(context, "Ton historique est conservé sous forme anonyme"), neutre: true),
        ]),
      ),
      const SizedBox(height: 20),

      Align(
        alignment: Alignment.centerLeft,
        child: Text(tr(context, "Tape SUPPRIMER pour confirmer"),
          style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      TextField(
        controller: _ctrl,
        onChanged: (v) => setState(() => _input = v),
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600, letterSpacing: 1),
        // Pas d'indication « SUPPRIMER » dans le champ : en capitales grasses,
        // elle passait pour un texte déjà saisi, et le bouton restait grisé
        // sans qu'on comprenne pourquoi. La consigne est juste au-dessus.
        decoration: InputDecoration(
          filled: true,
          fillColor: context.cl.surfaceD,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.cl.borderS)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.cl.error, width: 1.5)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _confirmed ? context.cl.error.withValues(alpha: 0.5) : context.cl.borderS,
              width: _confirmed ? 1.5 : 0.5)),
        ),
      ),
      const SizedBox(height: 20),

      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cl.textP,
            side: BorderSide(color: context.cl.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child:  Text(tr(context, "Annuler")),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: (_confirmed && !_loading) ? _deleteAccount : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.fondErreur,
            foregroundColor: Colors.white,
            disabledBackgroundColor: context.cl.error.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            :  Text(tr(context, "Supprimer"), style: TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ])),
  );

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    HapticFeedback.heavyImpact();
    try {
      await widget.ref.read(authProvider.notifier).deleteAccount();
      // Comme à la déconnexion : ce qui a été lu pour le compte supprimé
      // repart, et l'état de connexion avec. La déconnexion le faisait, pas la
      // suppression — la connexion suivante partait d'un « connecté » périmé.
      rafraichirDonneesCompte(widget.ref);
      widget.ref.invalidate(isLoggedInProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        afficherMessage(context, tr(context, "Erreur : {arg0}", [e]), type: TypeMessage.erreur);
      }
    }
  }
}

class _DeleteWarning extends StatelessWidget {
  final String text;
  /// Une information (ce qui est conservé), et non une perte.
  final bool neutre;
  const _DeleteWarning(this.text, {this.neutre = false});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      neutre
        ? Icon(Icons.info_outline_rounded, color: context.cl.textM, size: 14)
        : Icon(Icons.close_rounded, color: context.cl.error, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
        color: context.cl.textS, fontSize: 12, height: 1.4))),
    ],
  );
}

// ─── _ConfirmSheet ────────────────────────────────────────────────────────────
class _ConfirmSheet extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title, body, confirmLabel;
  final Color confirmColor;
  final Future<void> Function() onConfirm;
  const _ConfirmSheet({
    required this.icon, required this.iconColor,
    required this.title, required this.body,
    required this.confirmLabel, required this.confirmColor,
    required this.onConfirm,
  });
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}
class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _loading = false;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: widget.iconColor.withValues(alpha: 0.12),
          shape: BoxShape.circle),
        child: Icon(widget.icon, color: widget.iconColor, size: 32)),
      const SizedBox(height: 16),
      Text(widget.title, style: TextStyle(
        color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(widget.body, style: TextStyle(
        color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cl.textP,
            side: BorderSide(color: context.cl.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child:  Text(tr(context, "Annuler")),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: _loading ? null : () async {
            setState(() => _loading = true);
            await widget.onConfirm();
            if (mounted) setState(() => _loading = false);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(widget.confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ]),
  );
}

// ─── _AboutChip ───────────────────────────────────────────────────────────────
class _AboutChip extends StatelessWidget {
  final IconData? icon;

  /// Le vrai logo du réseau, à la place d'une icône générique.
  final Marque? marque;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _AboutChip({this.icon, this.marque, required this.label, required this.color, this.onTap})
      : assert(icon != null || marque != null);
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (marque != null) LogoMarque(marque!, taille: 14) else Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// La carte de la version installée : à jour, ou une mise à jour à installer.
class _CarteVersion extends ConsumerWidget {
  final String versionInstallee;
  const _CarteVersion({required this.versionInstallee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(_etatVersionProvider).valueOrNull;
    final version = etat?.courante ?? versionInstallee.replaceFirst('v', '');
    final aMettreAJour = etat?.disponible ?? false;
    final titre = aMettreAJour
        ? tr(context, "Une nouvelle version est disponible")
        : etat != null
            ? tr(context, "Vous utilisez la dernière version de l'appli")
            : tr(context, "Version de l'application");
    final contenu = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        const IconeReglage(Icons.smartphone_outlined),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(aMettreAJour
              ? tr(context, "{arg0} → {arg1} · Touche pour mettre à jour", [version, etat!.derniere ?? ''])
              : version,
            style: TextStyle(color: aMettreAJour ? context.cl.accent : context.cl.textS, fontSize: 12)),
        ])),
        if (aMettreAJour) Icon(Icons.chevron_right_rounded, size: 20, color: context.cl.textM),
      ]),
    );
    return Container(
      key: const Key('carte-version'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: aMettreAJour ? AppColors.primary.withValues(alpha: 0.5) : context.cl.border,
          width: aMettreAJour ? 1 : 0.5)),
      child: aMettreAJour
          ? InkWell(
              onTap: () => VersionService.proposer(etat!, estStore: ref.read(isStoreBuildProvider)),
              child: contenu)
          : contenu,
    );
  }
}
