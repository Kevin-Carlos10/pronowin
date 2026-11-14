import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../core/services/reglages_systeme.dart';
import '../../../core/theme/app_theme.dart';

/// « Être notifié » : l'explication avant la question du téléphone, comme
/// Sofascore (vidéo du 8 novembre 2026).
///
/// PronoWin posait la question au premier lancement, avant que la personne
/// sache ce qu'elle recevrait. Un « Ne pas autoriser » à ce moment-là est
/// définitif — iOS ne repose jamais la question — et plus aucune alerte de
/// but n'arrive. Désormais la question vient au moment où elle a un sens :
///
/// * au premier match suivi (`suivre_match.dart`) ;
/// * depuis Paramètres > Notifications ;
/// * sinon, une fois, à la deuxième ouverture de l'accueil au moins — pour
///   les nouveaux pronostics, qui ne dépendent d'aucun suivi.
///
/// « Plus tard » ne pose pas la question du téléphone : elle reste
/// disponible. L'explication ne revient pas avant [delaiEntrePropositions],
/// sauf au geste qui la justifie le plus (suivre un match).
class DemandeNotifications {
  DemandeNotifications._();

  static const _cleProposee = 'notif_explication_le';
  static const _cleOuvertures = 'notif_ouvertures_accueil';
  static const delaiEntrePropositions = Duration(days: 7);

  /// Explique, puis demande si la personne accepte. Vrai si les
  /// notifications sont autorisées à la fin.
  ///
  /// [motif] : la phrase qui dit ce qu'on recevra, selon le geste.
  static Future<bool> expliquerEtDemander(BuildContext context, {required String motif}) async {
    final etat = await ReglagesSysteme.lireEtat();
    if (etat == EtatNotifications.autorisees) return true;
    if (etat != EtatNotifications.aDemander || !context.mounted) return false;
    await _noterProposee();
    if (!context.mounted) return false;
    final oui = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeuilleEtreNotifie(motif: motif),
    );
    if (oui != true) return false;
    return ReglagesSysteme.demander();
  }

  /// À l'ouverture de l'accueil : une fois, à partir de la deuxième, si la
  /// question n'a jamais été posée ni proposée récemment.
  static Future<void> proposerALAccueil(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ouvertures = (prefs.getInt(_cleOuvertures) ?? 0) + 1;
      await prefs.setInt(_cleOuvertures, ouvertures);
      if (ouvertures < 2 || !_peutProposer(prefs)) return;
    } catch (_) {
      return;
    }
    if (await ReglagesSysteme.lireEtat() != EtatNotifications.aDemander) return;
    // Laisser l'accueil s'afficher ; et ne rien poser par-dessus une autre
    // fenêtre (mise à jour, code PIN…) : ce sera pour une autre ouverture.
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) return;
    await expliquerEtDemander(context,
        motif: tr(context, "Les nouveaux pronostics, les buts et les résultats des matchs que tu suis, dès qu'ils tombent."));
  }

  /// La proposition est-elle permise maintenant ?
  static Future<bool> peutProposer() async {
    try {
      return _peutProposer(await SharedPreferences.getInstance());
    } catch (_) {
      return false;
    }
  }

  static bool _peutProposer(SharedPreferences prefs) {
    final derniere = prefs.getInt(_cleProposee);
    if (derniere == null) return true;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(derniere)) >= delaiEntrePropositions;
  }

  static Future<void> _noterProposee() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cleProposee, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}

class _FeuilleEtreNotifie extends StatelessWidget {
  final String motif;
  const _FeuilleEtreNotifie({required this.motif});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      key: const Key('etre-notifie'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 30)),
          const SizedBox(height: 14),
          Text(tr(context, "Être notifié"),
            style: TextStyle(color: context.cl.textP, fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(motif, textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.4)),
          const SizedBox(height: 6),
          Text(tr(context, "Tu choisis ensuite quoi recevoir dans Paramètres."), textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.35)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              key: const Key('etre-notifie-autoriser'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, "Autoriser les notifications"),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('etre-notifie-plus-tard'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, "Plus tard"), style: TextStyle(color: context.cl.textS)),
          ),
        ]),
      ),
    ),
  );
}
