import 'package:pronowin/l10n/app_strings.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../domain/entities/match_entity.dart' show MatchEntity;
import '../../../../core/services/prono_share_service.dart';
import 'package:pronowin/core/utils/noms_equipes.dart';
import 'package:pronowin/core/config/sans_pari.dart';
import 'package:pronowin/shared/utils/premium_nav.dart';
import 'package:pronowin/shared/utils/retour.dart';

/// L'historique des pronostics publiés (refait le 25 octobre 2026).
///
/// Le serveur n'envoie que des pronostics réglés (`/pronostics/history`) :
/// gagnés, perdus, remboursés. La page avait un filtre « En attente »
/// toujours vide, un taux de réussite qui comptait les remboursés comme des
/// défaites, et des lignes qu'on ne pouvait pas ouvrir. Désormais : un bilan
/// juste (réussite sur les seuls gagnés et perdus, à partir de dix), la
/// série en cours, la réussite des gratuits et des Premium ; la liste par
/// jour, au modèle de Sofascore ; chaque ligne ouvre la fiche du match.

// ─── Filtres ──────────────────────────────────────────────────────────────────
enum _ResultFilter { all, win, loss, push }
enum _TierFilter { all, free, premium }
enum _PeriodFilter { week7, days30, days90 }

extension _PeriodExt on _PeriodFilter {
  int get days => switch (this) {
    _PeriodFilter.week7  => 7,
    _PeriodFilter.days30 => 30,
    _PeriodFilter.days90 => 90,
  };
  String get label => switch (this) {
    _PeriodFilter.week7  => trCurrent("7 jours"),
    _PeriodFilter.days30 => trCurrent("30 jours"),
    _PeriodFilter.days90 => trCurrent("90 jours"),
  };
}

// ─── Providers ────────────────────────────────────────────────────────────────
final _periodProvider = StateProvider.autoDispose<_PeriodFilter>(
  (ref) => _PeriodFilter.days30,
);
final _resultFilterProvider = StateProvider.autoDispose<_ResultFilter>(
  (ref) => _ResultFilter.all,
);
final _tierFilterProvider = StateProvider.autoDispose<_TierFilter>(
  (ref) => _TierFilter.all,
);

final historiqueProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, days) async {
  final cacheKey = 'pronostics_history_$days';
  try {
    final r    = await ref.read(dioProvider).get('/pronostics/history',
        queryParameters: {'days': days});
    final data = (r.data as List).cast<Map<String, dynamic>>();
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    return await CacheService.loadStale<List<Map<String, dynamic>>>(
        cacheKey, (d) => (d as List).cast<Map<String, dynamic>>()) ?? [];
  }
});

// ─── Bilan ────────────────────────────────────────────────────────────────────

/// Le bilan d'une liste de pronostics réglés, du plus récent au plus ancien
/// (l'ordre du serveur).
class BilanHistorique {
  final int gagnes, perdus, rembourses;
  /// Gagnés d'affilée en partant du plus récent ; un remboursé ne coupe pas
  /// la série, il ne la prolonge pas non plus.
  final int serieEnCours;
  final int meilleureSerie;
  const BilanHistorique({required this.gagnes, required this.perdus, required this.rembourses,
    required this.serieEnCours, required this.meilleureSerie});

  /// Sous ce nombre de pronostics gagnés ou perdus, pas de taux : le serveur
  /// fixe le même seuil (ECHANTILLON_MINIMAL) — se taire plutôt qu'annoncer
  /// 100 % ou 0 %.
  static const echantillon = 10;

  int get tranches => gagnes + perdus;

  /// Réussite sur les seuls gagnés et perdus. Elle divisait par tous les
  /// pronostics, remboursés compris.
  int? get taux => tranches >= echantillon
      ? (gagnes / tranches * 100).round()
      : null;

  factory BilanHistorique.de(Iterable<Map<String, dynamic>> entrees) {
    var g = 0, p = 0, r = 0;
    for (final e in entrees) {
      switch (e['result']) {
        case 'WIN':  g++;
        case 'LOSS': p++;
        case 'PUSH': r++;
      }
    }
    var enCours = 0;
    for (final e in entrees) {
      if (e['result'] == 'PUSH') continue;
      if (e['result'] != 'WIN') break;
      enCours++;
    }
    var meilleure = 0, courante = 0;
    for (final e in entrees.toList().reversed) {
      if (e['result'] == 'WIN') {
        courante++;
        if (courante > meilleure) meilleure = courante;
      } else if (e['result'] == 'LOSS') {
        courante = 0;
      }
    }
    return BilanHistorique(gagnes: g, perdus: p, rembourses: r,
      serieEnCours: enCours, meilleureSerie: meilleure);
  }
}

DateTime? _dateMatch(Map<String, dynamic> e) =>
    DateTime.tryParse(e['match']?['matchDate'] as String? ?? '')?.toLocal();

/// « Aujourd'hui », « Hier », « samedi 18 octobre ».
String libelleJour(BuildContext context, DateTime jour, {DateTime? maintenant}) {
  final n = maintenant ?? DateTime.now();
  final aujourdHui = DateTime(n.year, n.month, n.day);
  final j = DateTime(jour.year, jour.month, jour.day);
  final ecart = aujourdHui.difference(j).inDays;
  if (ecart == 0) return tr(context, "Aujourd'hui");
  if (ecart == 1) return tr(context, "Hier");
  final texte = DateFormat.MMMMEEEEd(AppStrings.of(context).locale.languageCode).format(j);
  return texte.isEmpty ? texte : texte[0].toUpperCase() + texte.substring(1);
}

// ─── Page ─────────────────────────────────────────────────────────────────────
class HistoriquePage extends ConsumerWidget {
  const HistoriquePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(_periodProvider);
    final sansPari = ref.watch(sansPariProvider);
    // Sur iPhone, l'historique sans ses cotes (`sansPariProvider`).
    final brut   = ref.watch(historiqueProvider(period.days));
    final async  = sansPari
        ? brut.whenData((l) => [for (final e in l) {...e}..remove('oddsRecommended')])
        : brut;
    final filtre = ref.watch(_resultFilterProvider);
    final niveau = ref.watch(_tierFilterProvider);

    Future<void> actualiser() async {
      ref.invalidate(historiqueProvider(period.days));
      await ref.read(historiqueProvider(period.days).future).catchError((_) => <Map<String, dynamic>>[]);
    }

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: context.cl.bg,
        leading: IconButton(
          tooltip: tr(context, "Retour"),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.cl.textP),
          // Ouverte par le « Bilan de la semaine », la page est seule dans la
          // pile : dépiler la fermait sans destination.
          onPressed: () => retourOuAller(context, repli: '/home'),
        ),
        title: Text(tr(context, "Historique"), style: TextStyle(
          color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          async.whenOrNull(
            data: (entries) => entries.isEmpty ? null : IconButton(
              icon: Icon(Icons.download_rounded, color: context.cl.textS, size: 22),
              tooltip: tr(context, "Exporter CSV"),
              onPressed: () => _exportCsv(context, entries, period, avecCotes: !sansPari),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error:   (_, _) => _ErrorView(onRetry: actualiser),
        data: (brutes) {
          // Du plus récent au plus ancien : la série en cours et l'ordre des
          // jours en dépendent. Le serveur les envoie ainsi ; on ne s'y fie pas.
          final all = [...brutes]..sort((a, b) =>
              (_dateMatch(b) ?? DateTime(2000)).compareTo(_dateMatch(a) ?? DateTime(2000)));
          final entries = _appliquer(all, filtre, niveau);
          final deuxNiveaux = all.any((e) => e['isPremium'] == true) && all.any((e) => e['isPremium'] != true);
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: actualiser,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              children: [
                _PeriodBar(selected: period,
                  onTap: (p) => ref.read(_periodProvider.notifier).state = p),
                const SizedBox(height: 14),
                if (all.isEmpty)
                  const _VideView(periode: true)
                else ...[
                  _StatsHeader(entrees: all, deuxNiveaux: deuxNiveaux)
                    .animate().fadeIn(duration: 350.ms).slideY(begin: -0.04, end: 0),
                  const SizedBox(height: 16),
                  if (BilanHistorique.de(all).tranches >= 2) ...[
                    _PerformanceChart(entries: all).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                    const SizedBox(height: 16),
                  ],
                  _ResultBar(selected: filtre, all: all,
                    onTap: (f) => ref.read(_resultFilterProvider.notifier).state = f),
                  if (deuxNiveaux)
                    _TierBar(selected: niveau,
                      onTap: (n) => ref.read(_tierFilterProvider.notifier).state = n),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    const _VideView(periode: false)
                  else
                    ..._parJour(context, entries),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static List<Map<String, dynamic>> _appliquer(
      List<Map<String, dynamic>> all, _ResultFilter f, _TierFilter n) => all.where((e) {
    final resultat = switch (f) {
      _ResultFilter.all  => true,
      _ResultFilter.win  => e['result'] == 'WIN',
      _ResultFilter.loss => e['result'] == 'LOSS',
      _ResultFilter.push => e['result'] == 'PUSH',
    };
    final niveau = switch (n) {
      _TierFilter.all     => true,
      _TierFilter.free    => e['isPremium'] != true,
      _TierFilter.premium => e['isPremium'] == true,
    };
    return resultat && niveau;
  }).toList();

  /// Une rubrique par jour, du plus récent au plus ancien.
  static List<Widget> _parJour(BuildContext context, List<Map<String, dynamic>> entries) {
    final jours = <DateTime, List<Map<String, dynamic>>>{};
    for (final e in entries) {
      final d = _dateMatch(e) ?? DateTime(2000);
      jours.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(e);
    }
    var rang = 0;
    return [
      for (final jour in jours.entries) ...[
        _DayHeader(label: libelleJour(context, jour.key), entries: jour.value),
        const SizedBox(height: 8),
        for (final e in jour.value)
          _EntryCard(entry: e)
            .animate(delay: Duration(milliseconds: (rang++).clamp(0, 12) * 35))
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
        const SizedBox(height: 14),
      ],
    ];
  }

  static void _exportCsv(BuildContext context,
      List<Map<String, dynamic>> entries, _PeriodFilter period, {required bool avecCotes}) {
    final buf = StringBuffer();
    // Sur iPhone, pas de colonne « Cote » : les cotes n'y sont pas servies.
    buf.writeln(avecCotes
        ? tr(context, "Date,Match,Ligue,Prédiction,Cote,Résultat")
        : tr(context, "Date,Match,Ligue,Prédiction,Résultat"));
    for (final e in entries) {
      final match  = e['match'] as Map<String, dynamic>? ?? {};
      final date   = match['matchDate'] as String? ?? '';
      final home   = nomEquipe(match['homeTeam']  as String? ?? '');
      final away   = nomEquipe(match['awayTeam']  as String? ?? '');
      final league = match['league']    as String? ?? '';
      final pred   = e['locked'] == true
          ? tr(context, "Pronostic Premium")
          : MatchEntity.applyTeamNames(
              e['predictionLabel'] as String? ?? '', homeTeam: home, awayTeam: away);
      final odds   = (e['oddsRecommended'] as num?)?.toStringAsFixed(2) ?? '';
      final result = switch (e['result'] as String?) {
        'WIN'  => tr(context, "Gagné"),
        'LOSS' => tr(context, "Perdu"),
        'PUSH' => tr(context, "Remboursé"),
        _      => tr(context, "En attente"),
      };
      buf.writeln(avecCotes
          ? '"$date","$home vs $away","$league","$pred",$odds,$result'
          : '"$date","$home vs $away","$league","$pred",$result');
    }
    final bytes = utf8.encode(buf.toString());
    final file = XFile.fromData(
      bytes,
      name:     'pronowin_historique_${period.days}j.csv',
      mimeType: 'text/csv',
    );
    // Même règle que l'image d'un pronostic : sur iOS, le fichier part seul,
    // sinon certaines applications ne gardent que le texte.
    PronoShareService.partagerFichiers(
      [file],
      texte: tr(context, "Historique PronoWin — {arg0}", [period.label]),
    );
  }
}

// ─── Pastilles ────────────────────────────────────────────────────────────────
class _Pastille extends StatelessWidget {
  final String label;
  final bool active;
  final Color couleur;
  final int? nombre;
  final VoidCallback onTap;
  final Key? cle;
  const _Pastille({required this.label, required this.active, required this.couleur,
    required this.onTap, this.nombre, this.cle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Semantics(
      button: true, selected: active,
      child: GestureDetector(
        key: cle,
        onTap: onTap,
        child: AnimatedContainer(
          duration: 220.ms,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color:  active ? couleur.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? couleur : context.cl.border, width: active ? 1.2 : 0.8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(
              color: active ? couleur : context.cl.textS, fontSize: 12, fontWeight: FontWeight.w700)),
            if (nombre != null) ...[
              const SizedBox(width: 5),
              Text('$nombre', style: TextStyle(
                color: active ? couleur : context.cl.textM, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    ),
  );
}

// ─── Barre période ────────────────────────────────────────────────────────────
class _PeriodBar extends StatelessWidget {
  final _PeriodFilter selected;
  final void Function(_PeriodFilter) onTap;
  const _PeriodBar({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Wrap(
    // Les pastilles passent à la ligne sur un écran étroit, ou texte agrandi.
    runSpacing: 8,
    children: [
      for (final p in _PeriodFilter.values)
        _Pastille(label: p.label, active: p == selected, couleur: AppColors.primary,
          cle: Key('historique-periode-${p.days}'), onTap: () => onTap(p)),
    ],
  );
}

// ─── Filtres résultat et niveau ───────────────────────────────────────────────
class _ResultBar extends StatelessWidget {
  final _ResultFilter selected;
  final List<Map<String, dynamic>> all;
  final void Function(_ResultFilter) onTap;
  const _ResultBar({required this.selected, required this.all, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = BilanHistorique.de(all);
    final specs = [
      (_ResultFilter.all,  tr(context, "Tous"),       context.cl.textP,   all.length),
      (_ResultFilter.win,  tr(context, "Gagnés"),     context.cl.success, b.gagnes),
      (_ResultFilter.loss, tr(context, "Perdus"),     context.cl.error,   b.perdus),
      // Le serveur n'envoie que des pronostics réglés : « En attente » était
      // toujours vide. Les remboursés, eux, n'avaient pas de filtre.
      if (b.rembourses > 0 || selected == _ResultFilter.push)
        (_ResultFilter.push, tr(context, "Remboursés"), context.cl.textS, b.rembourses),
    ];
    return Wrap(runSpacing: 8, children: [
      for (final (f, label, couleur, n) in specs)
        _Pastille(label: label, active: f == selected, couleur: couleur, nombre: n,
          cle: Key('historique-filtre-${f.name}'), onTap: () => onTap(f)),
    ]);
  }
}

class _TierBar extends StatelessWidget {
  final _TierFilter selected;
  final void Function(_TierFilter) onTap;
  const _TierBar({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(runSpacing: 8, children: [
      for (final (n, label) in [
        (_TierFilter.all, tr(context, "Tous les pronostics")),
        (_TierFilter.free, tr(context, "Gratuits")),
        (_TierFilter.premium, tr(context, "Premium")),
      ])
        _Pastille(label: label, active: n == selected,
          couleur: n == _TierFilter.premium ? context.cl.warning : AppColors.primary,
          cle: Key('historique-niveau-${n.name}'), onTap: () => onTap(n)),
    ]),
  );
}

// ─── Bilan ────────────────────────────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final List<Map<String, dynamic>> entrees;
  /// Gratuits et Premium dans la période : la réussite de chacun.
  final bool deuxNiveaux;
  const _StatsHeader({required this.entrees, required this.deuxNiveaux});

  @override
  Widget build(BuildContext context) {
    final b = BilanHistorique.de(entrees);
    final taux = b.taux;
    // Sans taux mesurable, aucune couleur de jugement : le gris dit
    // « pas encore mesuré », le rouge dirait « mauvais ».
    final color = taux == null ? context.cl.textM
                : taux >= 60   ? context.cl.success
                : taux >= 45   ? context.cl.warning
                :                context.cl.error;
    final compte = AppStrings.of(context);
    final gratuits = BilanHistorique.de(entrees.where((e) => e['isPremium'] != true));
    final premium  = BilanHistorique.de(entrees.where((e) => e['isPremium'] == true));

    return Container(
      key: const Key('historique-bilan'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.isDark ? const Color(0xFF151B2E) : Colors.white,
            context.isDark ? const Color(0xFF0D1220) : const Color(0xFFF8FAFC),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, "Réussite"), style: TextStyle(color: context.cl.textM, fontSize: 12)),
            const SizedBox(height: 2),
            Text(taux == null ? '—' : '$taux %', key: const Key('historique-taux'),
              style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 2),
            Text(taux == null
                ? tr(context, "Le taux s'affiche à partir de {arg0} pronostics gagnés ou perdus.", [BilanHistorique.echantillon])
                : tr(context, "sur {arg0} pronostics gagnés ou perdus", [b.tranches]),
              style: TextStyle(color: context.cl.textM, fontSize: 11.5, height: 1.35)),
          ])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tr(context, "Série en cours"), style: TextStyle(color: context.cl.textM, fontSize: 12)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (b.serieEnCours > 0)
                Icon(Icons.local_fire_department_rounded, color: context.cl.warning, size: 22),
              Text('${b.serieEnCours}', key: const Key('historique-serie'),
                style: TextStyle(color: b.serieEnCours > 0 ? context.cl.warning : context.cl.textP,
                  fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
            ]),
            const SizedBox(height: 2),
            Text(tr(context, "Meilleure : {arg0}", [b.meilleureSerie]),
              style: TextStyle(color: context.cl.textM, fontSize: 11.5)),
          ]),
        ]),
        const SizedBox(height: 14),
        // Gagnés, perdus, remboursés : la barre et sa légende.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            if (b.gagnes > 0) Expanded(flex: b.gagnes, child: Container(height: 8, color: context.cl.success)),
            if (b.perdus > 0) Expanded(flex: b.perdus, child: Container(height: 8,
              color: context.cl.error.withValues(alpha: 0.7))),
            if (b.rembourses > 0) Expanded(flex: b.rembourses, child: Container(height: 8,
              color: context.cl.textM.withValues(alpha: 0.5))),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _LegendDot(color: context.cl.success,
            label: compte.count(b.gagnes, one: '{arg0} gagné', other: '{arg0} gagnés')),
          _LegendDot(color: context.cl.error.withValues(alpha: 0.7),
            label: compte.count(b.perdus, one: '{arg0} perdu', other: '{arg0} perdus')),
          if (b.rembourses > 0)
            _LegendDot(color: context.cl.textM.withValues(alpha: 0.5),
              label: compte.count(b.rembourses, one: '{arg0} remboursé', other: '{arg0} remboursés')),
        ]),
        // La réussite de chaque niveau, dès qu'elle est mesurable.
        if (deuxNiveaux && (gratuits.taux != null || premium.taux != null)) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: context.cl.border),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (gratuits.taux != null)
              _Niveau(cle: const Key('historique-taux-gratuits'), icone: Icons.lock_open_rounded,
                couleur: AppColors.primary, texte: tr(context, "Gratuits : {arg0} %", [gratuits.taux])),
            if (premium.taux != null)
              _Niveau(cle: const Key('historique-taux-premium'), icone: Icons.workspace_premium_rounded,
                couleur: context.cl.warning, texte: tr(context, "Premium : {arg0} %", [premium.taux])),
          ]),
        ],
      ]),
    );
  }
}

class _Niveau extends StatelessWidget {
  final Key cle;
  final IconData icone;
  final Color couleur;
  final String texte;
  const _Niveau({required this.cle, required this.icone, required this.couleur, required this.texte});
  @override
  Widget build(BuildContext context) => Container(
    key: cle,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: couleur.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 14, color: couleur),
      const SizedBox(width: 5),
      Text(texte, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(color: context.cl.textM, fontSize: 11.5)),
  ]);
}

// ─── Graphe de performance ─────────────────────────────────────────────────
class _PerformanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  const _PerformanceChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    // Réussite cumulée, du plus ancien au plus récent, sur les seuls gagnés
    // et perdus : un remboursé n'est ni l'un ni l'autre.
    final tranches = entries
        .where((e) => e['result'] == 'WIN' || e['result'] == 'LOSS')
        .toList()
      ..sort((a, b) => (_dateMatch(a) ?? DateTime(2000)).compareTo(_dateMatch(b) ?? DateTime(2000)));

    int wins = 0;
    final spots = <FlSpot>[];
    for (int i = 0; i < tranches.length; i++) {
      if (tranches[i]['result'] == 'WIN') wins++;
      spots.add(FlSpot(i.toDouble(), wins / (i + 1) * 100));
    }

    final lastPct = spots.last.y;
    final color   = lastPct >= 60 ? context.cl.success
                  : lastPct >= 45 ? context.cl.warning
                  : context.cl.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text(tr(context, "Courbe de réussite"), style: TextStyle(
            color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ExcludeSemantics(child: LineChart(
            LineChartData(
              minY: 0, maxY: 100,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: context.cl.border, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: TextStyle(color: context.cl.textM, fontSize: 9)),
                  ),
                ),
                rightTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: color,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, _, _) {
                      final isLast = spot.x == spots.last.x;
                      return FlDotCirclePainter(
                        radius: isLast ? 5 : 0,
                        color: color,
                        strokeWidth: isLast ? 2 : 0,
                        strokeColor: context.cl.surface,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.00)],
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Ligne de référence 50 %
                LineChartBarData(
                  spots: [FlSpot(0, 50), FlSpot((tranches.length - 1).toDouble(), 50)],
                  isCurved: false,
                  color: context.cl.textM.withValues(alpha: 0.35),
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  dashArray: [4, 4],
                ),
              ],
            ),
          )),
        ),
      ]),
    );
  }
}

// ─── En-tête de jour ──────────────────────────────────────────────────────────
/// « Samedi 18 octobre » et le bilan du jour : une pastille par pronostic,
/// et les gagnés sur les gagnés ou perdus.
class _DayHeader extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> entries;
  const _DayHeader({required this.label, required this.entries});

  @override
  Widget build(BuildContext context) {
    final b = BilanHistorique.de(entries);
    Color couleur(Map<String, dynamic> e) => switch (e['result']) {
      'WIN'  => context.cl.success,
      'LOSS' => context.cl.error,
      _      => context.cl.textM,
    };
    return Semantics(
      header: true,
      label: tr(context, "{arg0} : {arg1} gagnés sur {arg2}", [label, b.gagnes, b.tranches]),
      child: ExcludeSemantics(child: Row(children: [
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
          color: context.cl.textP, fontSize: 13.5, fontWeight: FontWeight.w800))),
        for (final e in entries.take(8))
          Container(
            width: 7, height: 7, margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(color: couleur(e), shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('${b.gagnes}/${b.tranches}', style: TextStyle(
          color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()])),
      ])),
    );
  }
}

// ─── Ligne d'un pronostic ─────────────────────────────────────────────────────
/// Une ligne de l'historique, au modèle des résultats de Sofascore : les deux
/// équipes l'une sous l'autre avec leur logo et leur score, le pronostic, et
/// le résultat à droite. Elle ouvre la fiche du match.
///
/// Pronostic Premium et utilisateur non abonné (`locked`, décidé par le
/// serveur) : le match, le score et le résultat restent visibles, gagné comme
/// perdu ; le choix est remplacé par « Pronostic Premium » et un cadenas, et
/// la ligne mène vers l'offre Premium (décision de l'utilisateur du
/// 17 octobre 2026).
class _EntryCard extends ConsumerWidget {
  final Map<String, dynamic> entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verrouille = entry['locked'] == true;
    final premium    = entry['isPremium'] == true;
    final match      = entry['match'] as Map<String, dynamic>? ?? {};
    final result     = entry['result'] as String?;
    final isWin      = result == 'WIN';
    // Un remboursement (PUSH) s'affichait comme une défaite : croix rouge et
    // « LOSS », pour une mise rendue.
    final isPush     = result == 'PUSH';
    final isPending  = result == null;
    final homeTeam   = nomEquipe(match['homeTeam']  as String? ?? '');
    final awayTeam   = nomEquipe(match['awayTeam']  as String? ?? '');
    final homeScore  = match['homeScore'] as int?;
    final awayScore  = match['awayScore'] as int?;
    final league     = match['league']    as String? ?? '';
    final date       = _dateMatch(entry);
    final heure      = date != null ? DateFormat.Hm().format(date) : '';
    final pred       = verrouille
        ? tr(context, "Pronostic Premium")
        : MatchEntity.applyTeamNames(
            entry['predictionLabel'] as String? ?? '', homeTeam: homeTeam, awayTeam: awayTeam);
    final odds       = verrouille ? 0.0 : (entry['oddsRecommended'] as num?)?.toDouble() ?? 0.0;

    final resultColor = isPending ? context.cl.warning
                      : isWin    ? context.cl.success
                      : isPush   ? context.cl.textS
                      : context.cl.error;
    final libelleResultat = isPending ? tr(context, "En attente")
        : isWin  ? tr(context, "Gagné")
        : isPush ? tr(context, "Remboursé")
        : tr(context, "Perdu");

    Widget equipe(String nom, String? logo, int? score, int? adverse) {
      final gagne = score != null && adverse != null && score > adverse;
      return Row(children: [
        TeamLogoWidget(url: logo, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
          color: context.cl.textP, fontSize: 13.5, fontWeight: gagne ? FontWeight.w800 : FontWeight.w500))),
        const SizedBox(width: 8),
        Text(score?.toString() ?? '–', style: TextStyle(
          color: context.cl.textP, fontSize: 13.5, fontWeight: gagne ? FontWeight.w800 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()])),
      ]);
    }

    final carte = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: resultColor.withValues(alpha: 0.25), width: 0.8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Compétition et heure du coup d'envoi.
          Text([league, heure].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
          const SizedBox(height: 6),
          equipe(homeTeam, match['homeTeamLogo'] as String?, homeScore, awayScore),
          const SizedBox(height: 4),
          equipe(awayTeam, match['awayTeamLogo'] as String?, awayScore, homeScore),
          const SizedBox(height: 8),
          // Un libellé long (« Joueur va marquer un but à tout moment :
          // Mikel Oyarzabal ») se replie sur deux lignes, et la cote passe
          // dessous s'il le faut.
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Container(
              key: verrouille ? const Key('historique-premium-verrouille') : null,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (verrouille ? context.cl.warning : AppColors.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (verrouille) ...[
                  Icon(Icons.lock_rounded, size: 11, color: context.cl.warning),
                  const SizedBox(width: 4),
                ],
                Flexible(child: Text(pred, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(
                  color: verrouille ? context.cl.warning : context.cl.accent,
                  fontSize: 11.5, fontWeight: FontWeight.w700))),
              ])),
            if (odds > 0)
              Text('@ ${odds.toStringAsFixed(2)}',
                style: TextStyle(color: context.cl.textS, fontSize: 11.5)),
            // Un pronostic Premium ouvert à l'abonné : on le dit.
            if (premium && !verrouille)
              Icon(Icons.workspace_premium_rounded, size: 15, color: context.cl.warning,
                semanticLabel: tr(context, "Premium")),
          ]),
        ])),
        const SizedBox(width: 12),
        // Le résultat.
        SizedBox(width: 66, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: resultColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(
              isPending ? Icons.schedule_rounded
              : isWin  ? Icons.check_rounded
              : isPush ? Icons.undo_rounded
              : Icons.close_rounded,
              color: resultColor, size: 19)),
          const SizedBox(height: 4),
          Text(libelleResultat, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(color: resultColor, fontSize: 11, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );

    final id = entry['id'] as String?;
    return Semantics(
      button: true,
      hint: verrouille ? tr(context, "Débloquer avec Premium") : tr(context, "Voir la fiche du match"),
      child: InkWell(
        key: Key('historique-${id ?? ''}'),
        borderRadius: BorderRadius.circular(14),
        onTap: verrouille
            ? () => goToPremium(context, ref)
            : (id == null ? null : () => context.push('/pronostics/$id')),
        child: carte,
      ),
    );
  }
}

// ─── États vides / erreur ─────────────────────────────────────────────────────
class _VideView extends StatelessWidget {
  /// Rien sur la période (et non : rien pour ce filtre).
  final bool periode;
  const _VideView({required this.periode});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(children: [
      Icon(Icons.history_rounded, size: 56, color: context.cl.textM),
      const SizedBox(height: 16),
      Text(periode ? tr(context, "Aucun pronostic réglé sur cette période")
                   : tr(context, "Aucun résultat pour ce filtre"),
        textAlign: TextAlign.center,
        style: TextStyle(color: context.cl.textS, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(periode ? tr(context, "Les résultats apparaissent ici dès la fin des matchs. Essaie une période plus longue.")
                   : tr(context, "Essaie un autre filtre ou une période plus longue."),
        style: TextStyle(color: context.cl.textM, fontSize: 13),
        textAlign: TextAlign.center),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(tr(context, "Impossible de charger l'historique"),
        style: TextStyle(color: context.cl.textS)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onRetry, child: Text(tr(context, "Réessayer"))),
    ]));
}
