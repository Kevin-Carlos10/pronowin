// Carrousels — direct et carte héros — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _LiveMatchesCarousel extends StatelessWidget {
  final List<dynamic> matches;
  final bool isPremium;
  const _LiveMatchesCarousel({required this.matches, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    // Même widget de carte que « Pronostics du jour », donc strictement la
    // même taille : elle est portée par _hauteurCarrousel, pas recopiée.
    // La carte gère déjà le direct — bordure rouge, pastille LIVE, score au
    // centre à la place du « VS ».
    return SizedBox(
      height: _hauteurCarrousel(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final match = matches[i] as Map<String, dynamic>;
          final id    = match['id'] as String?;
          return SizedBox(
            width: MediaQuery.of(context).size.width * 0.84,
            child: _PronosticCard(
              prono: match,
              isPremium: isPremium,
              compact: true,
              onTap: id == null
                  ? () {}
                  : () {
                      HapticFeedback.lightImpact();
                      context.push('/pronostics/$id');
                    },
              // Verrouillé : on garde la porte d'entrée Premium d'origine.
              onLockedTap: () {
                HapticFeedback.lightImpact();
                showPremiumGateSheet(context,
                    matchLabel:
                        '${nomEquipe(match['home_team'] as String? ?? '')} vs ${nomEquipe(match['away_team'] as String? ?? '')}');
              },
            ),
          );
        },
      ),
    );
  }
}
