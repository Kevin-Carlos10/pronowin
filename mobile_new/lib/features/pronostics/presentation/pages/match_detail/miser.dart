// Bouton « J'ai misé » — extrait de match_detail_page.dart.
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

class _MiserButton extends ConsumerStatefulWidget {
  final MatchEntity match;
  const _MiserButton({required this.match});

  @override
  ConsumerState<_MiserButton> createState() => _MiserButtonState();
}

class _MiserButtonState extends ConsumerState<_MiserButton> {
  bool _betPlaced = false;

  @override
  Widget build(BuildContext context) {
    final alreadyBet = ref.watch(hasBetOnPronosticProvider(widget.match.id));

    if (_betPlaced || alreadyBet) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:  AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          SizedBox(width: 8),
          Text('Mise enregistrée dans ton bankroll',
              style: TextStyle(color: AppColors.success,
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return Semantics(
      button: true,
      label: 'Enregistrer cette mise dans ma bankroll',
      excludeSemantics: true,
      child: GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        // Miser suppose une bankroll, donc un compte. Sans cette garde, un
        // invité ouvrait la feuille qui échouait en 401 sur un message
        // générique — le dialogue ne diagnostique que le 404 « pas de
        // bankroll configurée ».
        if (!ref.read(effectiveLoggedInProvider)) {
          context.push(
            '/auth/email?from=${Uri.encodeComponent('/pronostics/${widget.match.id}')}');
          return;
        }
        final ok = await showMiserDialog(
          context,
          ref:              ref,
          pronosticId:      widget.match.id,
          homeTeam:         widget.match.homeTeam,
          awayTeam:         widget.match.awayTeam,
          predictionLabel:  widget.match.displayPredictionLabel,
          confidenceScore:  widget.match.confidenceScore,
          oddsRecommended:  widget.match.oddsRecommended,
        );
        if (ok) setState(() => _betPlaced = true);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, Color(0xFF059669)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: AppColors.success.withValues(alpha: 0.35),
            blurRadius: 14, offset: const Offset(0, 5))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.savings_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Valider ma mise',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Ajouter à mon bankroll',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('→', style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    ));
  }
}
