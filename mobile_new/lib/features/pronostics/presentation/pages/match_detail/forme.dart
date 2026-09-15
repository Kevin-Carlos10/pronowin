// Forme récente des équipes — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _FormCard extends StatelessWidget {
  final MatchEntity match;
  const _FormCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final total = match.homeFormPoints + match.awayFormPoints;
    final homeRatio = total > 0 ? match.homeFormPoints / total : 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardHeader(
          icon: Icons.trending_up_rounded,
          color: AppColors.success,
          title: 'Forme des équipes'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(match.homeTeam,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.success, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(match.awayTeam,
              textAlign: TextAlign.right,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.error, fontSize: 11.5,
                fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          Text('${match.homeFormPoints} pts',
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${match.awayFormPoints} pts',
            style: TextStyle(
              color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: homeRatio),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) => ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(
                  flex: (val * 1000).round().clamp(1, 999),
                  child: Container(color: AppColors.success)),
                Expanded(
                  flex: ((1 - val) * 1000).round().clamp(1, 999),
                  child: Container(color: AppColors.error)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
