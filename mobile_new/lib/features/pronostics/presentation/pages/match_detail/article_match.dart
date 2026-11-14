part of '../match_detail_page.dart';

/// L'avant-match ou le résumé du match, dans sa fiche (26 octobre 2026).
///
/// Le serveur en écrit plus de cent par semaine ; on ne les trouvait que dans
/// la page Actus. Avant le match, l'avant-match (classement, forme,
/// face-à-face, absents) ; après, le résumé. Le titre et deux lignes ; un
/// toucher ouvre l'article. Sans article, la carte disparaît, avec sa marge.
class _ArticleDuMatch extends ConsumerWidget {
  final String matchId;
  const _ArticleDuMatch({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(articlesDuMatchProvider(matchId)).valueOrNull;
    // Le résumé dès qu'il existe : il dit ce qui s'est passé.
    final news = (articles?['resume'] ?? articles?['avant_match']) as Map<String, dynamic>?;
    if (news == null) return const SizedBox.shrink();

    final avantMatch = estAvantMatch(news);
    final couleur = avantMatch ? context.cl.info : context.cl.success;
    final texte = editorialField(news, 'resume');
    final premierParagraphe = texte.split(RegExp(r'\n\s*\n')).map((p) => p.trim())
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        hint: tr(context, "Lire l'article complet"),
        child: Material(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const Key('fiche-article-match'),
            borderRadius: BorderRadius.circular(16),
            // Depuis la fiche : l'article n'y renvoie pas.
            onTap: () => ouvrirActu(context, ref, {...news, 'depuis_fiche': true}),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: couleur.withValues(alpha: 0.35), width: 0.8)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(avantMatch ? Icons.event_rounded : Icons.sports_soccer_rounded, size: 15, color: couleur),
                    const SizedBox(width: 6),
                    Text(avantMatch ? tr(context, "Avant-match") : tr(context, "Résumé"),
                      style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w800,
                        letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 8),
                  Text(titreActu(news), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w800, height: 1.3)),
                  if (premierParagraphe.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(premierParagraphe, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4)),
                  ],
                ])),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: context.cl.textM),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
