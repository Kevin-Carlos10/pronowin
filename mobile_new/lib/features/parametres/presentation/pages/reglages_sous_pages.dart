import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/config/contact_support.dart';
import '../../../../core/router/onglet_demarrage.dart';
import '../../../../core/services/reglages_systeme.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/messages.dart';
import '../../../../shared/widgets/logo_marque.dart';
import '../providers/settings_provider.dart';
import '../widgets/notifications_telephone.dart';
import '../../../../shared/utils/partage_parrainage.dart' show lienTelechargement;
import '../widgets/reglages_ui.dart';

// Les sous-pages des Paramètres (11 novembre 2026, comme 1xPartners) : les
// notifications et chaque liste de choix ont leur page, au lieu de cinq
// interrupteurs sur l'écran principal et de feuilles qui montent du bas.

/// Ouvre une sous-page par-dessus les Paramètres.
Future<void> ouvrirSousPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// « Notifications push » : tout mettre en pause, chaque catégorie, et les
/// réglages du téléphone.
class NotificationsReglagesPage extends ConsumerWidget {
  const NotificationsReglagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    // En pause, les catégories restent visibles mais figées : la reprise
    // rendra leurs réglages d'avant.
    final pause = s.notifPause;
    ValueChanged<bool>? bascule(String cle) => pause ? null : (_) => n.toggleNotif(cle);
    return PageReglages(
      titre: tr(context, "Notifications"),
      enfants: [
        // Coupées au niveau du téléphone : les interrupteurs n'y peuvent rien,
        // il faut le dire.
        const AlerteNotificationsTelephone(),
        // « Tout mettre en pause » de Threads, « Mode silencieux » de
        // Sofascore (11 novembre 2026).
        CarteReglages([
          LigneInterrupteur(
            key: const Key('notif-pause'),
            icone: Icons.notifications_paused_outlined,
            titre: tr(context, "Tout mettre en pause"),
            sousTitre: pause
                ? tr(context, "Aucune notification de PronoWin jusqu'à la reprise")
                : tr(context, "Coupe toutes les notifications d'un geste"),
            valeur: pause,
            onChanged: (v) async {
              await n.mettreNotifsEnPause(v);
              if (context.mounted) {
                afficherMessage(context, v
                    ? tr(context, "Toutes les notifications sont en pause")
                    : tr(context, "Notifications réactivées"),
                  type: v ? TypeMessage.info : TypeMessage.succes);
              }
            }),
        ]),
        const SizedBox(height: 22),
        EnTeteReglages(tr(context, "Notifications push")),
        CarteReglages([
          LigneInterrupteur(
            key: const Key('notif-match'),
            icone: Icons.sports_soccer_outlined,
            titre: tr(context, "Alertes matchs"), sousTitre: tr(context, "Pronostics, buts et résultats"),
            valeur: s.notifMatch, onChanged: bascule('match')),
          LigneInterrupteur(
            key: const Key('notif-promo'),
            icone: Icons.local_offer_outlined,
            titre: tr(context, "Offres & Promotions"), sousTitre: tr(context, "Codes promo et offres spéciales"),
            valeur: s.notifPromo, onChanged: bascule('promo')),
          LigneInterrupteur(
            key: const Key('notif-parrainage'),
            icone: Icons.people_outline_rounded,
            titre: tr(context, "Parrainage"), sousTitre: tr(context, "Quand un filleul s'abonne"),
            valeur: s.notifReferral, onChanged: bascule('referral')),
          LigneInterrupteur(
            key: const Key('notif-premium'),
            icone: Icons.workspace_premium_outlined,
            titre: tr(context, "Abonnement Premium"), sousTitre: tr(context, "Expiration et renouvellement"),
            valeur: s.notifPremium, onChanged: bascule('premium')),
        ]),
        const SizedBox(height: 22),
        EnTeteReglages(tr(context, "Téléphone")),
        CarteReglages([
          LigneReglage(
            icone: Icons.phone_iphone_outlined,
            titre: tr(context, "Réglages du téléphone"),
            sousTitre: tr(context, "Sons, bannières, écran verrouillé"),
            onTap: () => ReglagesSysteme.ouvrirNotifications()),
        ]),
      ],
    );
  }
}

/// Une liste de choix : langue, onglet d'ouverture. Le choix s'enregistre et
/// ramène aux Paramètres.
class ChoixReglagePage<T> extends StatelessWidget {
  final String titre;
  final String section;
  final List<({T valeur, String libelle, Widget? avant, Key? cle})> options;
  final T actuel;
  final ValueChanged<T> onChoisir;
  /// Une phrase sous la liste, au besoin.
  final String? note;
  const ChoixReglagePage({super.key, required this.titre, required this.section,
    required this.options, required this.actuel, required this.onChoisir, this.note});

  @override
  Widget build(BuildContext context) => PageReglages(
    titre: titre,
    enfants: [
      EnTeteReglages(section),
      CarteReglages([
        for (final o in options)
          LigneChoix(
            key: o.cle,
            titre: o.libelle, avant: o.avant, choisi: o.valeur == actuel,
            onTap: () {
              onChoisir(o.valeur);
              Navigator.of(context).maybePop();
            }),
      ]),
      if (note != null) Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
        child: Text(note!, style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.4))),
    ],
  );
}

// ─── Thème ─────────────────────────────────────────────────────────────────

/// Les quatre thèmes : leur réglage et leurs couleurs d'aperçu.
enum ChoixTheme {
  clair(ThemeMode.light, false),
  sombre(ThemeMode.dark, false),
  nocturne(ThemeMode.dark, true),
  systeme(ThemeMode.system, false);

  final ThemeMode mode;
  final bool noir;
  const ChoixTheme(this.mode, this.noir);

  static ChoixTheme depuis(AppSettings s) => switch (s.themeMode) {
    ThemeMode.light => clair,
    ThemeMode.system => systeme,
    ThemeMode.dark => s.nocturne ? nocturne : sombre,
  };
}

/// Le thème, choisi sur des aperçus comme chez 1xBet, et appliqué sur-le-
/// champ comme chez 1xPartners : la page reste ouverte, on voit le résultat.
class ChoixThemePage extends ConsumerWidget {
  const ChoixThemePage({super.key});

  String _libelle(BuildContext context, ChoixTheme c) => switch (c) {
    ChoixTheme.clair => tr(context, "Clair"),
    ChoixTheme.sombre => tr(context, "Sombre"),
    ChoixTheme.nocturne => tr(context, "Nocturne"),
    ChoixTheme.systeme => tr(context, "Système"),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actuel = ChoixTheme.depuis(ref.watch(settingsProvider));
    return PageReglages(
      titre: tr(context, "Thème"),
      enfants: [
        EnTeteReglages(tr(context, "Thème de l'application")),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cl.border, width: 0.5)),
          child: Row(children: [
            for (final c in ChoixTheme.values)
              Expanded(child: _VignetteTheme(
                key: Key('theme-${c.name}'),
                choix: c,
                libelle: _libelle(context, c),
                choisi: c == actuel,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(settingsProvider.notifier).setTheme(c.mode, nocturne: c.noir);
                },
              )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text(
            tr(context, "Nocturne : le sombre sur du noir pur, plus reposant la nuit et plus économe en batterie sur les écrans OLED. Système : clair ou sombre comme le téléphone."),
            style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.4)),
        ),
      ],
    );
  }
}

/// Un aperçu de thème : un petit écran, son nom, et un rond coché.
class _VignetteTheme extends StatelessWidget {
  final ChoixTheme choix;
  final String libelle;
  final bool choisi;
  final VoidCallback onTap;
  const _VignetteTheme({super.key, required this.choix, required this.libelle,
    required this.choisi, required this.onTap});

  /// Fond, carte et trait d'un écran miniature.
  static Widget _ecran(Color fond, Color carte, Color trait) => Container(
    color: fond,
    padding: const EdgeInsets.all(5),
    child: Column(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 4),
        Expanded(child: Container(
          decoration: BoxDecoration(
            color: carte, borderRadius: BorderRadius.circular(3),
            border: Border.all(color: trait, width: 0.5)))),
      ],
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final clair = _ecran(const Color(0xFFF5F7FA), Colors.white, const Color(0xFFE2E8F0));
    final sombre = _ecran(const Color(0xFF0A0E1A), const Color(0xFF151B2E), const Color(0xFF1E2A42));
    final apercu = switch (choix) {
      ChoixTheme.clair => clair,
      ChoixTheme.sombre => sombre,
      ChoixTheme.nocturne => _ecran(AppClNocturne.fond, AppClNocturne.carte, AppClNocturne.trait),
      ChoixTheme.systeme => Row(children: [Expanded(child: clair), Expanded(child: sombre)]),
    };
    return Semantics(
      button: true, selected: choisi, label: libelle,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ExcludeSemantics(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(children: [
            Container(
              width: 54, height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: choisi ? AppColors.primary : context.cl.borderS,
                  width: choisi ? 2 : 1)),
              child: apercu,
            ),
            const SizedBox(height: 8),
            Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: choisi ? context.cl.accent : context.cl.textS,
                fontSize: 12, fontWeight: choisi ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 8),
            Icon(choisi ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 22, color: choisi ? AppColors.primary : context.cl.textM),
          ]),
        )),
      ),
    );
  }
}

void ouvrirChoixTheme(BuildContext context, WidgetRef ref) =>
    ouvrirSousPage(context, const ChoixThemePage());

// ─── Langue, onglet d'ouverture ───────────────────────────────────────────

/// La langue : français ou anglais. Chaque langue s'écrit dans la sienne.
void ouvrirChoixLangue(BuildContext context, WidgetRef ref) {
  Widget drapeau(String d) => Text(d, style: const TextStyle(fontSize: 22));
  ouvrirSousPage(context, ChoixReglagePage<String>(
    titre: tr(context, "Langue"),
    section: tr(context, "Langue de l'application"),
    actuel: ref.read(settingsProvider).lang,
    options: [
      (valeur: 'fr', libelle: 'Français', avant: drapeau('🇫🇷'), cle: const Key('langue-fr')),
      (valeur: 'en', libelle: 'English', avant: drapeau('🇬🇧'), cle: const Key('langue-en')),
    ],
    onChoisir: (l) => ref.read(settingsProvider.notifier).setLang(l),
  ));
}

String libelleOnglet(BuildContext context, OngletDemarrage o) => switch (o) {
  OngletDemarrage.accueil => tr(context, "Accueil"),
  OngletDemarrage.pronos  => tr(context, "Pronos"),
  OngletDemarrage.suivis  => tr(context, "Suivis"),
};

/// L'écran sur lequel l'application s'ouvre (« Page principale » chez
/// 1xPartners, « Onglet principal » chez Sofascore).
void ouvrirChoixOnglet(BuildContext context, WidgetRef ref) {
  Icon icone(IconData i) => Icon(i, size: 22, color: context.cl.textP);
  ouvrirSousPage(context, ChoixReglagePage<OngletDemarrage>(
    titre: tr(context, "Onglet d'ouverture"),
    section: tr(context, "Écran d'ouverture"),
    actuel: ref.read(ongletDemarrageProvider),
    options: [
      (valeur: OngletDemarrage.accueil, libelle: libelleOnglet(context, OngletDemarrage.accueil),
        avant: icone(Icons.home_outlined), cle: const Key('onglet-accueil')),
      (valeur: OngletDemarrage.pronos, libelle: libelleOnglet(context, OngletDemarrage.pronos),
        avant: icone(Icons.sports_soccer_outlined), cle: const Key('onglet-pronos')),
      (valeur: OngletDemarrage.suivis, libelle: libelleOnglet(context, OngletDemarrage.suivis),
        avant: icone(Icons.notifications_active_outlined), cle: const Key('onglet-suivis')),
    ],
    note: tr(context, "L'écran sur lequel PronoWin s'ouvre, dès la prochaine fois."),
    onChoisir: (o) => enregistrerOngletDemarrage(ref, o),
  ));
}

// ─── Réseaux sociaux ──────────────────────────────────────────────────────

/// Les chaînes de PronoWin, d'une ligne chacune (« Réseaux sociaux » de
/// 1xBet, « Suivez-nous » de FotMob, 11 novembre 2026) : elles n'étaient
/// accessibles que depuis la fenêtre « À propos ».
class ReseauxSociauxPage extends StatelessWidget {
  const ReseauxSociauxPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget ligne({required Key cle, required Widget logo, required String titre,
        required String sousTitre, required VoidCallback onTap}) => InkWell(
      key: cle,
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            SizedBox(width: 26, height: 26, child: Center(child: logo)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(sousTitre, style: TextStyle(color: context.cl.textS, fontSize: 12)),
            ])),
            Icon(Icons.open_in_new_rounded, size: 18, color: context.cl.textM),
          ]),
        ),
      ),
    );
    return PageReglages(
      titre: tr(context, "Réseaux sociaux"),
      enfants: [
        EnTeteReglages(tr(context, "Suivre PronoWin")),
        CarteReglages([
          ligne(cle: const Key('reseau-telegram'), logo: const LogoMarque(Marque.telegram, taille: 24),
            titre: 'Telegram', sousTitre: tr(context, "La chaîne officielle"),
            onTap: ContactSupport.ouvrirTelegram),
          ligne(cle: const Key('reseau-whatsapp'), logo: const LogoMarque(Marque.whatsapp, taille: 24),
            titre: 'WhatsApp', sousTitre: tr(context, "La chaîne WhatsApp"),
            onTap: ContactSupport.ouvrirWhatsapp),
          ligne(cle: const Key('reseau-facebook'),
            logo: const Icon(Icons.facebook_rounded, size: 26, color: Color(0xFF1877F2)),
            titre: 'Facebook', sousTitre: tr(context, "La page Facebook"),
            onTap: ContactSupport.ouvrirFacebook),
        ]),
      ],
    );
  }
}

// ─── Partager par QR code ─────────────────────────────────────────────────

/// Partager l'application par QR code, comme 1xBet (11 novembre 2026) : un
/// ami scanne avec l'appareil photo et arrive sur le site, sans qu'on ait à
/// lui envoyer de lien — ni à dépenser ses données pour le faire.
class PartageQrPage extends StatelessWidget {
  /// Le code de parrainage de l'utilisateur connecté : la page qu'ouvre le
  /// code QR l'affiche, à saisir à l'inscription.
  final String? parrain;
  const PartageQrPage({super.key, this.parrain});

  @override
  Widget build(BuildContext context) => PageReglages(
    titre: tr(context, "Partager via QR code"),
    enfants: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.border, width: 0.5)),
        child: Column(children: [
          // Fond blanc dans tous les thèmes : un QR code se lit en noir sur
          // blanc, avec une marge claire autour.
          Container(
            key: const Key('qr-partage'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(
              data: lienTelechargement(parrain: parrain),
              size: 210,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0C1014)),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0C1014)),
              semanticsLabel: tr(context, "QR code du site de PronoWin"),
            ),
          ),
          const SizedBox(height: 18),
          Text(tr(context, "Fais scanner ce code"),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(parrain == null || parrain!.isEmpty
              ? tr(context, "Avec l'appareil photo du téléphone : il ouvre la page de téléchargement de PronoWin.")
              : tr(context, "Avec l'appareil photo du téléphone : il ouvre la page de téléchargement de PronoWin, avec ton code de parrainage."),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.45)),
          if (parrain != null && parrain!.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(parrain!, key: const Key('qr-code-parrain'), style: const TextStyle(
              color: Color(0xFFA78BFA), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      Builder(builder: (bouton) => OutlinedButton.icon(
        key: const Key('qr-partager-lien'),
        onPressed: () => partagerApplication(bouton, parrain: parrain),
        icon: const Icon(Icons.ios_share_outlined, size: 20),
        label: Text(tr(context, "Envoyer le lien à la place")),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.cl.textP,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: context.cl.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      )),
    ],
  );
}
