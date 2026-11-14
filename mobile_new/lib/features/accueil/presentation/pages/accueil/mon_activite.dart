// `part` : la carte regroupe des blocs privés de l'accueil.
part of '../accueil_page.dart';

/// « Mon activité » : la bankroll, les chiffres des pronostics et la méthode
/// en une carte repliable (revue de l'interface, 9 novembre 2026).
///
/// L'accueil empilait une quinzaine de sections ; ces trois-là, qui ne
/// parlent pas des matchs du jour, occupaient chacune la largeur de l'écran.
/// Repliée, la carte garde l'essentiel en une ligne (série, réussite) ; son
/// état est retenu d'une ouverture à l'autre.
class _MonActivite extends ConsumerStatefulWidget {
  final bool isPremium;
  final bool avecBankroll;
  const _MonActivite({required this.isPremium, required this.avecBankroll});

  @override
  ConsumerState<_MonActivite> createState() => _MonActiviteState();
}

const _cleActiviteOuverte = 'accueil_activite_ouverte';

class _MonActiviteState extends ConsumerState<_MonActivite> {
  bool _ouvert = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_cleActiviteOuverte) ?? false;
      if (mounted && v != _ouvert) setState(() => _ouvert = v);
    }).catchError((_) {});
  }

  void _basculer() {
    HapticFeedback.selectionClick();
    setState(() => _ouvert = !_ouvert);
    SharedPreferences.getInstance().then((p) => p.setBool(_cleActiviteOuverte, _ouvert)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsJourProvider).valueOrNull;
    final serie = stats?['streak'] as int? ?? 0;
    final reussite = stats?['winRate'] as int? ?? 0;
    final termines = stats?['totalFinished'] as int? ?? 0;
    final resume = [
      if (serie > 0) tr(context, "Série {arg0}", [serie]),
      if (termines >= 3) tr(context, "{arg0} % de réussite", [reussite]),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        key: const Key('mon-activite'),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: _ouvert,
            child: InkWell(
              key: const Key('mon-activite-entete'),
              borderRadius: BorderRadius.circular(16),
              onTap: _basculer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(children: [
                  Icon(Icons.insights_rounded, size: 18, color: context.cl.accent),
                  const SizedBox(width: 10),
                  Text(tr(context, "Mon activité"),
                    style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    _ouvert ? '' : (resume.isEmpty ? tr(context, "Bankroll, chiffres et méthode") : resume),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: TextStyle(color: context.cl.textS, fontSize: 12))),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _ouvert ? 0.5 : 0,
                    duration: context.duree(const Duration(milliseconds: 200)),
                    child: Icon(Icons.expand_more_rounded, color: context.cl.textS)),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: context.duree(const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_ouvert ? const SizedBox(width: double.infinity) : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.avecBankroll) const _BankrollMiniWidget(),
                _QuickStats(isPremium: widget.isPremium),
                const SizedBox(height: 12),
                _TutorielsBanner(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
