import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pronowin/l10n/app_strings.dart';
import '../../../../core/config/contact_support.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/montant.dart';
import '../../../parametres/presentation/widgets/reglages_ui.dart' show EnTeteReglages;

/// Une ligne de l'historique des paiements (`GET /subscriptions/historique`).
class LignePaiement {
  final String id;
  final DateTime date;
  /// paye | offert | en_cours | en_verification | refuse | echoue | a_verifier | rembourse
  final String statut;
  /// premium_monthly | premium_annual
  final String? formule;
  final int? montant;
  /// geniuspay | manual_mobcash | iap_apple | iap_google | manual_admin | promo | autre
  final String moyen;
  final String? operateur, reference, motif;
  final DateTime? debut, fin;

  const LignePaiement({required this.id, required this.date, required this.statut,
    this.formule, this.montant, required this.moyen, this.operateur, this.reference,
    this.motif, this.debut, this.fin});

  factory LignePaiement.fromJson(Map<String, dynamic> j) => LignePaiement(
    id:        j['id'] as String,
    date:      DateTime.parse(j['date'] as String).toLocal(),
    statut:    j['statut'] as String? ?? 'paye',
    formule:   j['formule'] as String?,
    montant:   (j['montant'] as num?)?.round(),
    moyen:     j['moyen'] as String? ?? 'autre',
    operateur: j['operateur'] as String?,
    reference: j['reference'] as String?,
    motif:     j['motif'] as String?,
    debut:     DateTime.tryParse(j['debut'] as String? ?? '')?.toLocal(),
    fin:       DateTime.tryParse(j['fin'] as String? ?? '')?.toLocal(),
  );

  /// Un paiement abouti : il a son reçu.
  bool get abouti => statut == 'paye' || statut == 'offert';
}

final historiquePaiementsProvider = FutureProvider.autoDispose<List<LignePaiement>>((ref) async {
  final r = await ref.read(dioProvider).get('/subscriptions/historique');
  final liste = ((r.data as Map<String, dynamic>)['paiements'] as List<dynamic>?) ?? const [];
  return [for (final e in liste) LignePaiement.fromJson(e as Map<String, dynamic>)];
});

/// « Orange Money », « Moov Money » : le nom de l'opérateur choisi chez GeniusPay.
String nomOperateur(String code) => switch (code) {
  'orange_money' => 'Orange Money',
  'moov_money'   => 'Moov Money',
  'wave'         => 'Wave',
  'mtn_money'    => 'MTN MoMo',
  'coris_money'  => 'Coris Money',
  _ => code.split('_').where((m) => m.isNotEmpty)
      .map((m) => '${m[0].toUpperCase()}${m.substring(1)}').join(' '),
};

String libelleMoyen(BuildContext context, LignePaiement l) => switch (l.moyen) {
  'geniuspay'      => l.operateur == null
      ? tr(context, "Mobile Money")
      : tr(context, "Mobile Money ({arg0})", [nomOperateur(l.operateur!)]),
  'manual_mobcash' => tr(context, "Mobile Money (transfert)"),
  'iap_apple'      => 'App Store',
  'iap_google'     => 'Google Play',
  'manual_admin'   => tr(context, "Offert par PronoWin"),
  'promo'          => tr(context, "Code partenaire"),
  _                => tr(context, "Autre moyen"),
};

String libelleFormule(BuildContext context, String? formule) => switch (formule) {
  'premium_annual'  => tr(context, "Premium annuel"),
  'premium_monthly' => tr(context, "Premium mensuel"),
  _                 => 'Premium',
};

/// Libellé, couleur et icône d'un statut.
(String, Color, IconData) apparenceStatut(BuildContext context, String statut) => switch (statut) {
  'paye'            => (tr(context, "Payé"), context.cl.success, Icons.check_circle_rounded),
  'offert'          => (tr(context, "Offert"), context.cl.info, Icons.card_giftcard_rounded),
  'en_cours'        => (tr(context, "En cours"), context.cl.warning, Icons.schedule_rounded),
  'en_verification' => (tr(context, "En vérification"), context.cl.warning, Icons.hourglass_top_rounded),
  'a_verifier'      => (tr(context, "À vérifier par l'équipe"), context.cl.warning, Icons.support_agent_rounded),
  'rembourse'       => (tr(context, "Remboursé"), context.cl.info, Icons.undo_rounded),
  'refuse'          => (tr(context, "Refusé"), context.cl.error, Icons.cancel_rounded),
  _                 => (tr(context, "Échoué"), context.cl.error, Icons.error_outline_rounded),
};

/// « 6 000 FCFA » ; « — » quand on l'ignore (achat de boutique). Un mois
/// offert vaut « 0 FCFA » : son statut dit déjà « Offert ».
String _montant(BuildContext context, LignePaiement l) =>
    l.montant == null ? '—' : '${montantExact(l.montant!)} FCFA';

/// L'historique des paiements et leurs reçus (23 novembre 2026).
///
/// Payer par Mobile Money ne laissait aucune trace côté abonné : ni relevé
/// de boutique, ni reçu. D'où des « j'ai payé, où est mon Premium ? » quand
/// une validation tarde. Ici : ce qui a été payé et jusqu'à quand, ce qui est
/// en cours, ce qui a été refusé et pourquoi — et un reçu à partager.
class HistoriquePaiementsPage extends ConsumerWidget {
  const HistoriquePaiementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historique = ref.watch(historiquePaiementsProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(tr(context, "Historique des paiements"),
          style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(historiquePaiementsProvider.future),
        child: historique.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, _) => _Message(
            icone: Icons.cloud_off_rounded,
            texte: tr(context, "L'historique est momentanément indisponible."),
            reessayer: () => ref.invalidate(historiquePaiementsProvider)),
          data: (lignes) => lignes.isEmpty
              ? _Message(icone: Icons.receipt_long_outlined,
                  texte: tr(context, "Aucun paiement pour l'instant. Tes paiements Premium s'afficheront ici, avec leur reçu."))
              : ListView(
                  key: const Key('historique-paiements'),
                  padding: const EdgeInsets.fromLTRB(margeEcran, 12, margeEcran, 40),
                  children: [
                    EnTeteReglages(tr(context, "Tes paiements")),
                    Container(
                      decoration: BoxDecoration(
                        color: context.cl.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.cl.border, width: 0.5)),
                      child: Column(children: [
                        for (final (i, l) in lignes.indexed) ...[
                          if (i > 0) Divider(height: 1, indent: 62, color: context.cl.border),
                          _LignePaiementTuile(ligne: l),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Text(tr(context, "Touche un paiement pour voir son reçu. Une question ? Écris-nous depuis le reçu."),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LignePaiementTuile extends StatelessWidget {
  final LignePaiement ligne;
  const _LignePaiementTuile({required this.ligne});

  @override
  Widget build(BuildContext context) {
    final (statut, couleur, icone) = apparenceStatut(context, ligne.statut);
    final langue = AppStrings.of(context).locale.languageCode;
    return InkWell(
      key: Key('paiement-${ligne.id}'),
      onTap: () {
        HapticFeedback.selectionClick();
        ouvrirRecu(context, ligne);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: couleur.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icone, size: 20, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(libelleFormule(context, ligne.formule),
              style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${DateFormat('d MMM y', langue).format(ligne.date)} · ${libelleMoyen(context, ligne)}',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.cl.textS, fontSize: 13)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_montant(context, ligne),
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(statut, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

/// Le texte du reçu, à partager.
String texteRecu(BuildContext context, LignePaiement l) {
  final langue = AppStrings.of(context).locale.languageCode;
  final jour = DateFormat('d MMMM y', langue);
  final (statut, _, _) = apparenceStatut(context, l.statut);
  return [
    tr(context, "Reçu PronoWin"),
    '${tr(context, "Formule")} : ${libelleFormule(context, l.formule)}',
    '${tr(context, "Montant")} : ${_montant(context, l)}',
    '${tr(context, "Moyen de paiement")} : ${libelleMoyen(context, l)}',
    '${tr(context, "Date")} : ${jour.format(l.date)}',
    if (l.debut != null && l.fin != null)
      '${tr(context, "Période")} : ${tr(context, "du {arg0} au {arg1}", [jour.format(l.debut!), jour.format(l.fin!)])}',
    if (l.reference != null) '${tr(context, "Référence")} : ${l.reference}',
    '${tr(context, "Statut")} : $statut',
  ].join('\n');
}

/// Le reçu d'un paiement : le détail, et selon le cas le partager ou écrire
/// au support.
void ouvrirRecu(BuildContext context, LignePaiement l) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cl.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (feuille) {
      final langue = AppStrings.of(feuille).locale.languageCode;
      final jour = DateFormat('d MMMM y', langue);
      final (statut, couleur, icone) = apparenceStatut(feuille, l.statut);
      Widget ligne(String libelle, String valeur) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(libelle,
            style: TextStyle(color: feuille.cl.textS, fontSize: 13))),
          Expanded(child: Text(valeur, textAlign: TextAlign.end,
            style: TextStyle(color: feuille.cl.textP, fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: feuille.cl.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Icon(icone, color: couleur, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(feuille, "Reçu"),
                style: TextStyle(color: feuille.cl.textP, fontSize: 18, fontWeight: FontWeight.w700))),
              Text(statut, key: const Key('recu-statut'),
                style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            ligne(tr(feuille, "Formule"), libelleFormule(feuille, l.formule)),
            ligne(tr(feuille, "Montant"), _montant(feuille, l)),
            ligne(tr(feuille, "Moyen de paiement"), libelleMoyen(feuille, l)),
            ligne(tr(feuille, "Date"), jour.format(l.date)),
            if (l.debut != null && l.fin != null)
              ligne(tr(feuille, "Période"), tr(feuille, "du {arg0} au {arg1}", [jour.format(l.debut!), jour.format(l.fin!)])),
            if (l.reference != null) ligne(tr(feuille, "Référence"), l.reference!),
            if (l.motif != null && l.motif!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('recu-motif'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: feuille.cl.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: feuille.cl.error.withValues(alpha: 0.25))),
                child: Text(tr(feuille, "Motif : {arg0}", [l.motif!]),
                  style: TextStyle(color: feuille.cl.textP, fontSize: 13, height: 1.4)),
              ),
            ],
            if (l.statut == 'en_cours' || l.statut == 'en_verification') ...[
              const SizedBox(height: 8),
              Text(tr(feuille, "Ton Premium s'active dès que le paiement est confirmé. Tu recevras une notification."),
                style: TextStyle(color: feuille.cl.textS, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 18),
            if (l.abouti)
              FilledButton.icon(
                key: const Key('recu-partager'),
                onPressed: () {
                  final boite = feuille.findRenderObject() as RenderBox?;
                  Share.share(texteRecu(feuille, l), subject: tr(feuille, "Reçu PronoWin"),
                    sharePositionOrigin: boite == null ? null : boite.localToGlobal(Offset.zero) & boite.size);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(tr(feuille, "Partager le reçu")),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('recu-support'),
              // L'objet porte la référence : la demande se traite sans
              // échange préalable.
              onPressed: () => ContactSupport.ouvrirEmail(
                sujet: tr(feuille, "Paiement Premium — {arg0}", [l.reference ?? jour.format(l.date)]),
                corps: texteRecu(feuille, l)),
              style: OutlinedButton.styleFrom(
                foregroundColor: feuille.cl.textP,
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: feuille.cl.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.mail_outline_rounded, size: 18),
              label: Text(tr(feuille, "Une question sur ce paiement ?")),
            ),
          ]),
        ),
      );
    },
  );
}

class _Message extends StatelessWidget {
  final IconData icone;
  final String texte;
  final VoidCallback? reessayer;
  const _Message({required this.icone, required this.texte, this.reessayer});

  @override
  Widget build(BuildContext context) => ListView(
    // Une liste, pour que « tirer pour actualiser » marche aussi ici.
    padding: const EdgeInsets.fromLTRB(32, 80, 32, 40),
    children: [
      Icon(icone, size: 40, color: context.cl.textM),
      const SizedBox(height: 12),
      Text(texte, textAlign: TextAlign.center,
        style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.45)),
      if (reessayer != null) ...[
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: reessayer, child: Text(tr(context, "Réessayer")))),
      ],
    ],
  );
}
