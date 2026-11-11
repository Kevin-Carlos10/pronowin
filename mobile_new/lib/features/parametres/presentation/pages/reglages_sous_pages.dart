import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/router/onglet_demarrage.dart';
import '../../../../core/services/reglages_systeme.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/notifications_telephone.dart';
import '../widgets/reglages_ui.dart';

// Les sous-pages des Paramètres (11 novembre 2026, comme 1xPartners) : les
// notifications et chaque liste de choix ont leur page, au lieu de cinq
// interrupteurs sur l'écran principal et de feuilles qui montent du bas.

/// Ouvre une sous-page par-dessus les Paramètres.
Future<void> ouvrirSousPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// « Notifications push » : ce que PronoWin envoie, et les réglages du
/// téléphone.
class NotificationsReglagesPage extends ConsumerWidget {
  const NotificationsReglagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return PageReglages(
      titre: tr(context, "Notifications"),
      enfants: [
        // Coupées au niveau du téléphone : les interrupteurs n'y peuvent rien,
        // il faut le dire.
        const AlerteNotificationsTelephone(),
        EnTeteReglages(tr(context, "Notifications push")),
        CarteReglages([
          LigneInterrupteur(
            key: const Key('notif-match'),
            icone: Icons.sports_soccer_rounded,
            titre: tr(context, "Alertes matchs"), sousTitre: tr(context, "Pronostics, buts et résultats"),
            valeur: s.notifMatch, onChanged: (_) => n.toggleNotif('match')),
          LigneInterrupteur(
            key: const Key('notif-promo'),
            icone: Icons.local_offer_rounded,
            titre: tr(context, "Offres & Promotions"), sousTitre: tr(context, "Codes promo et offres spéciales"),
            valeur: s.notifPromo, onChanged: (_) => n.toggleNotif('promo')),
          LigneInterrupteur(
            key: const Key('notif-parrainage'),
            icone: Icons.people_rounded,
            titre: tr(context, "Parrainage"), sousTitre: tr(context, "Quand un filleul s'abonne"),
            valeur: s.notifReferral, onChanged: (_) => n.toggleNotif('referral')),
          LigneInterrupteur(
            key: const Key('notif-premium'),
            icone: Icons.workspace_premium_rounded,
            titre: tr(context, "Abonnement Premium"), sousTitre: tr(context, "Expiration et renouvellement"),
            valeur: s.notifPremium, onChanged: (_) => n.toggleNotif('premium')),
        ]),
        const SizedBox(height: 22),
        EnTeteReglages(tr(context, "Téléphone")),
        CarteReglages([
          LigneReglage(
            icone: Icons.phone_iphone_rounded,
            titre: tr(context, "Réglages du téléphone"),
            sousTitre: tr(context, "Sons, bannières, écran verrouillé"),
            onTap: () => ReglagesSysteme.ouvrirNotifications()),
        ]),
      ],
    );
  }
}

/// Une liste de choix : thème, langue, onglet d'ouverture. Le choix
/// s'enregistre et ramène aux Paramètres.
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

/// Le thème : sombre, clair, ou celui du téléphone.
void ouvrirChoixTheme(BuildContext context, WidgetRef ref) {
  Icon icone(IconData i) => Icon(i, size: 20, color: context.cl.textS);
  ouvrirSousPage(context, ChoixReglagePage<ThemeMode>(
    titre: tr(context, "Thème"),
    section: tr(context, "Thème de l'application"),
    actuel: ref.read(settingsProvider).themeMode,
    options: [
      (valeur: ThemeMode.dark, libelle: tr(context, "Sombre"), avant: icone(Icons.dark_mode_rounded), cle: const Key('theme-sombre')),
      (valeur: ThemeMode.light, libelle: tr(context, "Clair"), avant: icone(Icons.light_mode_rounded), cle: const Key('theme-clair')),
      (valeur: ThemeMode.system, libelle: tr(context, "Système"), avant: icone(Icons.brightness_auto_rounded), cle: const Key('theme-systeme')),
    ],
    onChoisir: (m) => ref.read(settingsProvider.notifier).setTheme(m),
  ));
}

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
  Icon icone(IconData i) => Icon(i, size: 20, color: context.cl.textS);
  ouvrirSousPage(context, ChoixReglagePage<OngletDemarrage>(
    titre: tr(context, "Onglet d'ouverture"),
    section: tr(context, "Écran d'ouverture"),
    actuel: ref.read(ongletDemarrageProvider),
    options: [
      (valeur: OngletDemarrage.accueil, libelle: libelleOnglet(context, OngletDemarrage.accueil),
        avant: icone(Icons.home_rounded), cle: const Key('onglet-accueil')),
      (valeur: OngletDemarrage.pronos, libelle: libelleOnglet(context, OngletDemarrage.pronos),
        avant: icone(Icons.sports_soccer_rounded), cle: const Key('onglet-pronos')),
      (valeur: OngletDemarrage.suivis, libelle: libelleOnglet(context, OngletDemarrage.suivis),
        avant: icone(Icons.notifications_active_rounded), cle: const Key('onglet-suivis')),
    ],
    note: tr(context, "L'écran sur lequel PronoWin s'ouvre, dès la prochaine fois."),
    onChoisir: (o) => enregistrerOngletDemarrage(ref, o),
  ));
}
