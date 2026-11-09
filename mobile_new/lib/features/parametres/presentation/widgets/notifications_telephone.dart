import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/reglages_systeme.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../notifications/presentation/demande_notifications.dart';
import '../../../../shared/utils/messages.dart';

/// En tête de la rubrique Notifications : les notifications sont coupées
/// au niveau du téléphone, les interrupteurs en dessous n'y peuvent rien.
///
/// Repris de Sofascore (vidéo du 8 novembre 2026). Relu au retour dans
/// l'application : on revient des réglages du téléphone, l'encart disparaît.
class AlerteNotificationsTelephone extends StatefulWidget {
  const AlerteNotificationsTelephone({super.key});

  @override
  State<AlerteNotificationsTelephone> createState() => _AlerteNotificationsTelephoneState();
}

class _AlerteNotificationsTelephoneState extends State<AlerteNotificationsTelephone>
    with WidgetsBindingObserver {
  EtatNotifications _etat = EtatNotifications.inconnu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) _relire();
  }

  Future<void> _relire() async {
    final etat = await ReglagesSysteme.lireEtat();
    if (mounted && etat != _etat) setState(() => _etat = etat);
  }

  Future<void> _activer() async {
    await DemandeNotifications.expliquerEtDemander(context,
        motif: tr(context, "Les nouveaux pronostics, les buts et les résultats des matchs que tu suis, dès qu'ils tombent."));
    await _relire();
  }

  @override
  Widget build(BuildContext context) {
    final coupees = _etat == EtatNotifications.refusees;
    if (!coupees && _etat != EtatNotifications.aDemander) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: Key(coupees ? 'notifications-telephone-coupees' : 'notifications-a-activer'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: context.cl.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.warning.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.notifications_off_rounded, color: context.cl.warning, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(coupees
                ? tr(context, "Les notifications sont coupées sur ce téléphone")
                : tr(context, "Les notifications ne sont pas encore activées"),
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(tr(context, "Ni buts, ni coups d'envoi, ni résultats ne t'arriveront tant qu'elles le restent."),
              style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.35)),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: context.cl.accent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: coupees ? () => ReglagesSysteme.ouvrirNotifications() : _activer,
              icon: Icon(coupees ? Icons.settings_rounded : Icons.notifications_active_rounded, size: 18),
              label: Text(coupees ? tr(context, "Ouvrir les réglages") : tr(context, "Activer les notifications"),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ])),
        ]),
      ),
    );
  }
}

/// Le message envoyé par « Partager l'application ».
///
/// Rien sur le pari : le même texte part de la version iPhone, et le site
/// n'est cité que comme adresse.
String messagePartageApplication(BuildContext context) => tr(context,
    "Je suis les matchs sur PronoWin : scores en direct, statistiques et analyses de foot. {arg0}",
    [AppConstants.siteUrl]);

/// « Partager l'application », comme Sofascore. [contexte] : celui de la
/// ligne touchée, qui ancre la feuille sur iPad. Si la feuille ne s'ouvre
/// pas, le message est copié.
Future<void> partagerApplication(BuildContext contexte) async {
  final message = messagePartageApplication(contexte);
  final messager = ScaffoldMessenger.maybeOf(contexte);
  final copie = tr(contexte, "Message copié : colle-le dans WhatsApp, un SMS…");
  Rect? origine;
  final boite = contexte.findRenderObject();
  if (boite is RenderBox && boite.hasSize && boite.attached) {
    final zone = boite.localToGlobal(Offset.zero) & boite.size;
    if (!zone.isEmpty) origine = zone;
  }
  try {
    await Share.share(message, subject: 'PronoWin', sharePositionOrigin: origine);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: message));
    afficherMessageVia(messager, copie, type: TypeMessage.succes);
  }
}
