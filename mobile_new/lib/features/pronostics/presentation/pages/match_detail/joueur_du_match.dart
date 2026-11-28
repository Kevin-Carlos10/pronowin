part of '../match_detail_page.dart';

/// « Joueur du match » — le vote des fans (8 novembre 2026), comme la
/// « Course au Joueur du Match » de Sofascore.
///
/// Avant la 80e minute : la course aux notes (les trois mieux notés) et
/// « Le vote des fans s'ouvre à la 80e minute ». Ensuite : les mieux notés,
/// à toucher pour voter ; puis la répartition, son propre vote en évidence.
/// Clos le lendemain du match, le résultat reste. Rien n'est misé.
class _JoueurDuMatch extends ConsumerStatefulWidget {
  final MatchEntity match;
  const _JoueurDuMatch({required this.match});

  @override
  ConsumerState<_JoueurDuMatch> createState() => _JoueurDuMatchState();
}

class _JoueurDuMatchState extends ConsumerState<_JoueurDuMatch> {
  VotesJoueurDuMatch? _apresVote;
  int? _envoi;
  String? _erreur;
  /// Revenir à la liste des joueurs pour changer son vote.
  bool _changer = false;

  Future<void> _voter(int joueurId) async {
    if (_envoi != null) return;
    HapticFeedback.selectionClick();
    final match = widget.match;
    if (!ref.read(effectiveLoggedInProvider)) {
      context.push('/auth/email?from=${Uri.encodeComponent('/pronostics/${match.id}')}');
      return;
    }
    final impossible = tr(context, "Vote impossible pour l'instant.");
    setState(() { _envoi = joueurId; _erreur = null; });
    try {
      final r = await ref.read(voterJoueurDuMatchProvider)(match.id, joueurId);
      if (!mounted) return;
      setState(() { _apresVote = r; _envoi = null; _changer = false; });
    } on DioException catch (e) {
      if (!mounted) return;
      final message = e.response?.data is Map ? (e.response!.data as Map)['message'] as String? : null;
      setState(() { _envoi = null; _erreur = message ?? impossible; });
      if (e.response?.statusCode == 409) ref.invalidate(joueurDuMatchProvider(match.id));
    } catch (_) {
      if (!mounted) return;
      setState(() { _envoi = null; _erreur = impossible; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    if (match.status == MatchStatus.upcoming) return const SizedBox.shrink();
    final v = _apresVote ?? ref.watch(joueurDuMatchProvider(match.id)).valueOrNull;
    if (v == null || v.etat == 'indisponible' || (v.etat == 'clos' && v.total == 0)) return const SizedBox.shrink();
    final notes = ref.watch(playerRatingsProvider(match.id)).valueOrNull ?? const <PlayerRating>[];
    final resultats = !_changer && (v.monVote != null || v.etat == 'clos');
    final compte = AppStrings.of(context);

    Widget entete() => Row(children: [
      const Icon(Icons.military_tech_rounded, size: 19, color: AppColors.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(tr(context, "Joueur du match"),
        style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w800))),
      if (v.total > 0)
        Text(compte.count(v.total, one: '{arg0} vote', other: '{arg0} votes'),
          style: TextStyle(color: context.cl.textM, fontSize: 12)),
    ]);

    Widget ligneJoueur(PlayerRating j, {required bool meilleur}) => InkWell(
      key: Key('joueur-du-match-${j.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: v.ouvert && j.id != null ? () => _voter(j.id!) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          TeamLogoWidget(url: j.team == 'home' ? match.homeTeamLogo : match.awayTeamLogo, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600))),
          if (_envoi == j.id)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            PastilleNote(j.rating, taille: 11, meilleur: meilleur),
            if (v.ouvert) ...[
              const SizedBox(width: 10),
              Icon(Icons.how_to_vote_rounded, size: 18, color: context.cl.accent),
            ],
          ],
        ]),
      ),
    );

    final List<Widget> corps;
    if (v.etat == 'bientot') {
      // La course aux notes, comme Sofascore avant l'ouverture.
      corps = [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
          child: Text(tr(context, "Le vote des fans s'ouvre à la {arg0}e minute", [v.minuteOuverture]),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.accent, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tr(context, "La course aux notes"),
            style: TextStyle(color: context.cl.textM, fontSize: 12, fontWeight: FontWeight.w600)),
          for (final (i, j) in notes.take(3).indexed) ligneJoueur(j, meilleur: i == 0),
        ],
      ];
    } else if (!resultats) {
      // Ouvert, pas encore voté (ou changement d'avis) : les mieux notés.
      final choix = notes.where((j) => j.id != null).take(8).toList();
      corps = [
        Text(tr(context, "Touche le joueur qui t'a le plus impressionné."),
          style: TextStyle(color: context.cl.textS, fontSize: 13)),
        const SizedBox(height: 6),
        if (choix.isEmpty)
          Text(tr(context, "Les notes des joueurs ne sont pas encore disponibles."),
            style: TextStyle(color: context.cl.textM, fontSize: 13))
        else
          for (final (i, j) in choix.indexed) ligneJoueur(j, meilleur: i == 0),
      ];
    } else {
      corps = [
        for (final c in v.classement)
          Padding(
            key: Key('joueur-du-match-part-${c.joueurId}'),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TeamLogoWidget(url: c.equipe == 'home' ? match.homeTeamLogo : match.awayTeamLogo, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(c.nom, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cl.textP, fontSize: 13,
                    fontWeight: v.monVote == c.joueurId ? FontWeight.w800 : FontWeight.w600))),
                if (v.monVote == c.joueurId) ...[
                  Icon(Icons.check_circle_rounded, size: 15, color: context.cl.accent),
                  const SizedBox(width: 6),
                ],
                Text('${c.pourcentage} %', style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c.pourcentage / 100, minHeight: 5,
                  backgroundColor: context.cl.surfaceD,
                  color: v.monVote == c.joueurId ? AppColors.primary : context.cl.textM)),
            ]),
          ),
        const SizedBox(height: 4),
        if (v.ouvert)
          TextButton(
            key: const Key('joueur-du-match-changer'),
            onPressed: () => setState(() => _changer = true),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            child: Text(tr(context, "Changer mon vote")))
        else
          Text(tr(context, "Votes clos."), style: TextStyle(color: context.cl.textM, fontSize: 12)),
      ];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('joueur-du-match'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cl.border, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          entete(),
          const SizedBox(height: 10),
          ...corps,
          if (_erreur != null) ...[
            const SizedBox(height: 6),
            Text(_erreur!, key: const Key('joueur-du-match-erreur'),
              style: TextStyle(color: context.cl.error, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}
