import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../../../core/config/sans_pari.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/messages.dart';
import '../../../../shared/utils/montant.dart';
import '../../../../shared/utils/retour.dart';
import '../../../pronostics/data/models/match_model.dart';
import '../../../pronostics/domain/entities/match_entity.dart';
import '../providers/bankroll_provider.dart';
import '../widgets/carte_couverture.dart';

/// Les coupons combinés de la bankroll (27 novembre 2026).
///
/// Décisions de l'utilisateur : de 2 à 10 sélections ; des pronostics PronoWin
/// publiés et ouverts, ou des sélections libres que l'abonné règle lui-même ;
/// la mise suit le barème de la sélection la moins sûre (une sélection libre
/// compte pour la note 1). Comme une mise simple, elle est calculée par le
/// serveur et verrouillée.

const combineMin = 2;
const combineMax = 10;

String _messageServeur(Object e) {
  if (e is DioException && e.response?.data is Map) {
    final m = (e.response!.data as Map)['message'];
    if (m is String && m.isNotEmpty) return m;
  }
  return '';
}

// ─── Les pronostics qu'on peut combiner ──────────────────────────────────────

/// Les pronostics principaux publiés, à venir et ouverts à l'abonné.
final pronosticsCombinablesProvider = FutureProvider.autoDispose<List<MatchEntity>>((ref) async {
  final r = await ref.read(dioProvider).get('/pronostics', queryParameters: {
    'status': 'upcoming', 'has_pronostic': 'true', 'limit': 50,
  });
  final liste = (r.data as Map)['data'] as List? ?? const [];
  final maintenant = DateTime.now();
  return liste
      .map((e) => MatchModel.fromJson((e as Map).cast<String, dynamic>()) as MatchEntity)
      .where((m) => m.hasPronostic && !m.isLocked && m.oddsRecommended > 1 && m.matchDate.isAfter(maintenant))
      .toList();
});

/// Une sélection en cours de composition.
class _Choisie {
  final String? pronosticId;
  final String rencontre;
  final String selection;
  final double cote;
  const _Choisie({this.pronosticId, required this.rencontre, required this.selection, required this.cote});
  bool get libre => pronosticId == null;

  Map<String, dynamic> get pourApi => libre
      ? {'libre': {'match': rencontre, 'selection': selection, 'cote': cote}}
      : {'pronostic_id': pronosticId};
}

// ─── Nouveau combiné ─────────────────────────────────────────────────────────

class NouveauCombinePage extends ConsumerStatefulWidget {
  const NouveauCombinePage({super.key});
  @override
  ConsumerState<NouveauCombinePage> createState() => _NouveauCombinePageState();
}

class _NouveauCombinePageState extends ConsumerState<NouveauCombinePage> {
  final List<_Choisie> _choisies = [];
  Map<String, dynamic>? _apercu;
  String? _erreurApercu;
  bool _envoi = false;
  int _requete = 0;

  double get _coteTotale => _choisies.fold<double>(1, (p, c) => p * c.cote);

  Future<void> _actualiser() async {
    final n = ++_requete;
    if (_choisies.length < combineMin) {
      setState(() { _apercu = null; _erreurApercu = null; });
      return;
    }
    try {
      final r = await ref.read(dioProvider).post('/bankroll/combines/apercu',
          data: {'selections': _choisies.map((c) => c.pourApi).toList()});
      if (!mounted || n != _requete) return;
      setState(() { _apercu = Map<String, dynamic>.from(r.data as Map); _erreurApercu = null; });
    } catch (e) {
      if (!mounted || n != _requete) return;
      setState(() { _apercu = null; _erreurApercu = _messageServeur(e); });
    }
  }

  void _basculer(MatchEntity m) {
    setState(() {
      final i = _choisies.indexWhere((c) => c.pronosticId == m.id);
      if (i >= 0) {
        _choisies.removeAt(i);
      } else if (_choisies.length < combineMax) {
        _choisies.add(_Choisie(
          pronosticId: m.id, rencontre: '${m.homeTeam} – ${m.awayTeam}',
          selection: m.displayPredictionLabel, cote: m.oddsRecommended));
      }
    });
    _actualiser();
  }

  Future<void> _ajouterLibre() async {
    if (_choisies.length >= combineMax) return;
    final libre = await showDialog<_Choisie>(context: context, builder: (_) => const _DialogueSelectionLibre());
    if (libre == null || !mounted) return;
    setState(() => _choisies.add(libre));
    _actualiser();
  }

  Future<void> _valider() async {
    final apercu = _apercu;
    if (apercu == null || _envoi) return;
    setState(() => _envoi = true);
    try {
      final r = await ref.read(dioProvider).post('/bankroll/combines', data: {
        'selections': _choisies.map((c) => c.pourApi).toList(),
        'staked_amount': apercu['mise'],
      });
      if (!mounted) return;
      ref.invalidate(bankrollProvider);
      afficherMessage(context, tr(context, "Combiné enregistré ✅"), type: TypeMessage.succes);
      final id = (r.data as Map)['id'] as String?;
      if (id != null) {
        context.pushReplacement('/bankroll/combine/$id');
      } else {
        retourOuAller(context, repli: '/bankroll');
      }
    } catch (e) {
      if (!mounted) return;
      final code = e is DioException && e.response?.data is Map ? (e.response!.data as Map)['code'] : null;
      if (code == 'STAKE_CHANGED') await _actualiser();
      if (!mounted) return;
      final m = _messageServeur(e);
      afficherMessage(context, m.isNotEmpty ? m : tr(context, "Le combiné n’a pas pu être enregistré. Réessaie."), type: TypeMessage.erreur);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pronos = ref.watch(pronosticsCombinablesProvider);
    final devise = nomDevise(ref.watch(bankrollProvider).valueOrNull?.currency);
    final apercu = _apercu;
    final plein = _choisies.length >= combineMax;

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg, elevation: 0, scrolledUnderElevation: 0,
        title: Text(tr(context, "Nouveau combiné"), style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: context.cl.textP),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(tr(context, "Combine de 2 à 10 sélections en un seul coupon. Il passe si toutes passent."),
          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4)),
        const SizedBox(height: 16),

        // ── Le coupon ────────────────────────────────────────────────────
        Container(
          key: const Key('combine-coupon'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cl.border, width: 0.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, "Ton coupon ({arg0}/{arg1})", [_choisies.length, combineMax]),
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_choisies.isEmpty)
              Text(tr(context, "Choisis au moins deux sélections ci-dessous."),
                style: TextStyle(color: context.cl.textM, fontSize: 12))
            else
              for (final (i, c) in _choisies.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.rencontre, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(c.libre ? tr(context, "{arg0} · sélection libre", [c.selection]) : c.selection,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.cl.textM, fontSize: 11)),
                    ])),
                    Text(c.cote.toStringAsFixed(2), style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
                    IconButton(
                      key: Key('combine-retirer-$i'),
                      tooltip: tr(context, "Retirer"),
                      icon: Icon(Icons.close_rounded, size: 18, color: context.cl.textM),
                      onPressed: () { setState(() => _choisies.removeAt(i)); _actualiser(); },
                    ),
                  ]),
                ),
            if (_choisies.length >= combineMin) ...[
              Divider(color: context.cl.border, height: 18),
              Text(tr(context, "Cote totale {arg0}", [_coteTotale.toStringAsFixed(2)]),
                key: const Key('combine-cote-totale'),
                style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (apercu != null) ...[
                Text(tr(context, "Mise {arg0} {arg1} · gain potentiel {arg2} {arg1}",
                    [montantExact((apercu['mise'] as num).toDouble()), devise, montantExact((apercu['gain_potentiel'] as num).toDouble())]),
                  key: const Key('combine-mise'),
                  style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(tr(context, "La mise suit le barème de la sélection la moins sûre (note {arg0}) ; une sélection libre compte pour la note 1.",
                    [(apercu['note_retenue'] as num?)?.toInt() ?? 1]),
                  style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.35)),
              ] else if (_erreurApercu != null && _erreurApercu!.isNotEmpty)
                Text(_erreurApercu!, key: const Key('combine-erreur'),
                  style: TextStyle(color: context.cl.error, fontSize: 12, height: 1.35)),
            ],
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(
              key: const Key('combine-valider'),
              onPressed: apercu != null && !_envoi ? _valider : null,
              child: Text(_envoi ? tr(context, "Enregistrement…") : tr(context, "Valider le combiné")),
            )),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Les sélections ───────────────────────────────────────────────
        Row(children: [
          Expanded(child: Text(tr(context, "Pronostics PronoWin"),
            style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700))),
          TextButton.icon(
            key: const Key('combine-ajouter-libre'),
            onPressed: plein ? null : _ajouterLibre,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr(context, "Sélection libre")),
          ),
        ]),
        const SizedBox(height: 4),
        pronos.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (_, _) => Text(tr(context, "Les pronostics n’ont pas pu être chargés."),
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
          data: (liste) => liste.isEmpty
              ? Text(tr(context, "Aucun pronostic à venir pour l’instant. Tu peux ajouter des sélections libres."),
                  style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.4))
              : Column(children: [
                  for (final m in liste)
                    _LignePronostic(
                      match: m,
                      choisi: _choisies.any((c) => c.pronosticId == m.id),
                      desactive: plein && !_choisies.any((c) => c.pronosticId == m.id),
                      onTap: () => _basculer(m),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _LignePronostic extends StatelessWidget {
  final MatchEntity match;
  final bool choisi;
  final bool desactive;
  final VoidCallback onTap;
  const _LignePronostic({required this.match, required this.choisi, required this.desactive, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key('combine-prono-${match.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: desactive ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
            border: Border.all(color: choisi ? AppColors.primaryBouton : context.cl.border, width: choisi ? 1.2 : 0.5)),
          child: Row(children: [
            Icon(choisi ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 20, color: choisi ? AppColors.primaryBouton : context.cl.textM),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${match.homeTeam} – ${match.awayTeam}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(match.displayPredictionLabel, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cl.textM, fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            Text(match.oddsRecommended.toStringAsFixed(2),
              style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ),
  );
}

/// Une sélection hors PronoWin : le match, la sélection et sa cote.
class _DialogueSelectionLibre extends StatefulWidget {
  const _DialogueSelectionLibre();
  @override
  State<_DialogueSelectionLibre> createState() => _DialogueSelectionLibreState();
}

class _DialogueSelectionLibreState extends State<_DialogueSelectionLibre> {
  final _match = TextEditingController();
  final _selection = TextEditingController();
  final _cote = TextEditingController();

  @override
  void dispose() {
    _match.dispose();
    _selection.dispose();
    _cote.dispose();
    super.dispose();
  }

  double? get _coteLue => double.tryParse(_cote.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final cote = _coteLue;
    final valide = _match.text.trim().length >= 2 && _selection.text.trim().length >= 2
        && cote != null && cote >= 1.01 && cote <= 1000;
    return AlertDialog(
      backgroundColor: context.cl.surface,
      title: Text(tr(context, "Sélection libre"), style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, "Une sélection hors PronoWin : tu régleras toi-même son résultat, et elle ne se couvre pas."),
          style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
        const SizedBox(height: 10),
        TextField(key: const Key('libre-match'), controller: _match, maxLength: 80,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr(context, "Match"), hintText: tr(context, "PSG – Marseille"))),
        TextField(key: const Key('libre-selection'), controller: _selection, maxLength: 80,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr(context, "Sélection"), hintText: tr(context, "PSG gagne"))),
        TextField(key: const Key('libre-cote'), controller: _cote,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: tr(context, "Cote"))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, "Annuler"))),
        TextButton(
          key: const Key('libre-ajouter'),
          onPressed: valide
              ? () => Navigator.pop(context, _Choisie(
                  rencontre: _match.text.trim(), selection: _selection.text.trim(), cote: cote))
              : null,
          child: Text(tr(context, "Ajouter"), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── Détail d'un combiné ─────────────────────────────────────────────────────

/// La couverture d'un combiné, maintenant (serveur).
final couvertureCombineProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/bankroll/combines/$id/couverture');
    return Map<String, dynamic>.from(r.data as Map);
  } catch (_) {
    return null;
  }
});

/// Le libellé d'un résultat.
String libelleResultat(BuildContext context, String? r) => switch (r) {
  'WIN' => tr(context, "gagné"),
  'LOSS' => tr(context, "perdu"),
  'PUSH' => tr(context, "remboursé"),
  _ => tr(context, "en cours"),
};

Color couleurResultat(BuildContext context, String? r) => switch (r) {
  'WIN' => context.cl.success,
  'LOSS' => context.cl.error,
  'PUSH' => context.cl.info,
  _ => context.cl.warning,
};

class CombineDetailPage extends ConsumerWidget {
  final String id;
  const CombineDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargement = ref.watch(bankrollProvider).isLoading;
    final c = ref.watch(combineProvider(id));
    // Le retour du téléphone aussi : sans historique, il remonte à la bankroll
    // au lieu de quitter l'app.
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (aQuitte, _) { if (!aQuitte) context.go('/bankroll'); },
      child: Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg, elevation: 0, scrolledUnderElevation: 0,
        // Ouvert depuis une notification, l'écran n'a pas d'historique : sans
        // ce bouton, aucune flèche, et le retour du téléphone quittait l'app.
        leading: IconButton(
          key: const Key('combine-retour'),
          tooltip: tr(context, "Retour"),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => retourOuAller(context, repli: '/bankroll'),
        ),
        title: Text(tr(context, "Combiné"), style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: context.cl.textP),
      ),
      body: c == null
          ? Center(child: chargement
              ? const CircularProgressIndicator()
              : Text(tr(context, "Combiné introuvable."), style: TextStyle(color: context.cl.textM)))
          : _DetailCombine(combine: c),
    ));
  }
}

class _DetailCombine extends ConsumerWidget {
  final BankrollCombine combine;
  const _DetailCombine({required this.combine});

  Future<void> _regler(BuildContext context, WidgetRef ref, SelectionCombine l, String? result) async {
    try {
      await ref.read(dioProvider).post('/bankroll/combines/${combine.id}/selections/${l.id}/resultat',
          data: {'result': result});
      ref.invalidate(bankrollProvider);
      ref.invalidate(couvertureCombineProvider(combine.id));
    } catch (e) {
      if (!context.mounted) return;
      final m = _messageServeur(e);
      afficherMessage(context, m.isNotEmpty ? m : tr(context, "Le résultat n’a pas pu être enregistré. Réessaie."), type: TypeMessage.erreur);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = combine;
    final devise = nomDevise(c.currency);
    final net = c.resultatNet;
    final couleur = couleurResultat(context, c.result);
    final sansPari = ref.watch(sansPariProvider);
    final couverture = sansPari || c.result != null ? null : ref.watch(couvertureCombineProvider(c.id)).valueOrNull;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Container(
        key: Key('combine-entete-${c.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: couleur.withValues(alpha: 0.4), width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(context, "{arg0} sélections · cote {arg1}", [c.selections.length, c.oddsUsed.toStringAsFixed(2)]),
              style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: couleur.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
              child: Text(libelleResultat(context, c.result),
                style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(tr(context, "Mise {arg0} {arg1}", [montantExact(c.stakedAmount), devise]),
            style: TextStyle(color: context.cl.textS, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            net != null
                ? tr(context, "Résultat net {arg0} {arg1}", ['${net >= 0 ? '+' : ''}${montantExact(net)}', devise])
                : tr(context, "Gain potentiel {arg0} {arg1}", [montantExact(c.potentialGain), devise]),
            key: const Key('combine-resultat'),
            style: TextStyle(color: net == null ? context.cl.textP : (net >= 0 ? context.cl.success : context.cl.error),
              fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(height: 16),
      for (final l in c.selections)
        _LigneSelection(
          ligne: l,
          // Une sélection libre se règle à la main, et se corrige aussi.
          reglable: l.libre,
          onRegler: (r) => _regler(context, ref, l, r),
        ),
      const SizedBox(height: 8),
      if (couverture != null && (couverture['enregistree'] is Map || couverture['disponible'] == true || couverture['raison'] == 'cote'))
        CarteCouverture(
          donnees: couverture, cle: c.id, combine: true,
          apresEnregistrement: () => ref.invalidate(couvertureCombineProvider(c.id)),
        )
      else if (c.couvertureEnregistree != null)
        CarteCouverture(donnees: {
          'enregistree': {
            'id': c.couvertureEnregistree!.id, 'selection_fr': c.couvertureEnregistree!.selectionFr,
            'selection_en': c.couvertureEnregistree!.selectionEn, 'strategie': c.couvertureEnregistree!.strategie,
            'mise': c.couvertureEnregistree!.mise, 'cote': c.couvertureEnregistree!.cote,
            'result': c.couvertureEnregistree!.result, 'profit': c.couvertureEnregistree!.profit,
          },
          'devise': c.currency,
        }, cle: c.id, combine: true)
      else if (!sansPari && c.result == null)
        Text(tr(context, "La couverture s’ouvre quand il ne reste qu’une sélection PronoWin à jouer, toutes les autres passées."),
          key: const Key('combine-couverture-plus-tard'),
          style: TextStyle(color: context.cl.textM, fontSize: 12, height: 1.4)),
      const SizedBox(height: 12),
      Text(tr(context, "Une sélection remboursée ou annulée compte pour une cote de 1. Le classement ne compte pas les combinés."),
        style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.4)),
    ]);
  }
}

class _LigneSelection extends StatelessWidget {
  final SelectionCombine ligne;
  final bool reglable;
  final ValueChanged<String?> onRegler;
  const _LigneSelection({required this.ligne, required this.reglable, required this.onRegler});

  @override
  Widget build(BuildContext context) {
    final l = ligne;
    final couleur = couleurResultat(context, l.result);
    return Container(
      key: Key('combine-selection-${l.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.rencontre, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600))),
          Text(l.cote.toStringAsFixed(2), style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 2),
        Text(l.selection, style: TextStyle(color: context.cl.textM, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(l.annulee ? tr(context, "annulée") : libelleResultat(context, l.result),
              style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          if (l.libre) ...[
            const SizedBox(width: 8),
            Text(tr(context, "sélection libre"), style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ],
        ]),
        if (reglable) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final (r, libelle) in [('WIN', tr(context, "Gagnée")), ('LOSS', tr(context, "Perdue")), ('PUSH', tr(context, "Remboursée"))])
              ChoiceChip(
                key: Key('combine-regler-${l.id}-$r'),
                label: Text(libelle),
                selected: l.result == r,
                showCheckmark: false,
                // Toucher le résultat choisi l'annule.
                onSelected: (_) => onRegler(l.result == r ? null : r),
              ),
          ]),
        ],
      ]),
    );
  }
}
