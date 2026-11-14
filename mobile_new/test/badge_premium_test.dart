import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'package:pronowin/shared/widgets/badge_premium.dart';
import 'aides/banc_ecran.dart';

/// Le badge bleu des membres Premium, comme sur Instagram (20 octobre 2026).
void main() {
  setUpAll(preparerBanc);

  test('le serveur dit qui est Premium ; un ancien serveur, personne', () {
    PronosticComment lire(Map<String, dynamic> user) => PronosticComment.fromJson({
      'id': 'c', 'userId': 'u', 'content': 'Avis', 'createdAt': '2026-10-20T10:00:00Z', 'user': user});
    expect(lire({'pseudo': 'Awa', 'isPremium': true}).userPremium, isTrue);
    expect(lire({'pseudo': 'Issa', 'isPremium': false}).userPremium, isFalse);
    expect(lire({'pseudo': 'Moussa'}).userPremium, isFalse);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('dans les commentaires : à côté du nom des seuls membres Premium (${theme.brightness.name})', (t) async {
      final r = await mesurerEcran(t,
        ecran: const Scaffold(body: SingleChildScrollView(child: CommentsSection(pronosticId: 'm'))),
        theme: theme, echelle: 1.8,
        surcharges: [commentsProvider('m').overrideWith((ref) async => CommentsData(
          vote: const PronosticVoteData(agree: 0, disagree: 0, total: 0),
          comments: [
            PronosticComment(id: '1', userId: 'a', content: 'Arsenal gagne', isExpert: false,
              createdAt: DateTime(2026, 10, 20), userPseudo: 'Awa_avec_un_pseudo_tres_long', userPremium: true),
            PronosticComment(id: '2', userId: 'b', content: 'Nul', isExpert: false,
              createdAt: DateTime(2026, 10, 20), userPseudo: 'Issa'),
          ]))],
        verifier: () {
          expect(find.byType(BadgePremium), findsOneWidget);
          expect(find.bySemanticsLabel('Membre Premium'), findsOneWidget);
          final badge = t.getRect(find.byType(BadgePremium));
          expect(badge.top, lessThan(t.getRect(find.text('Arsenal gagne')).top));
        });
      expect(r.debordements, isEmpty);
      expect(r.autres, isEmpty);
    });
  }

  testWidgets('une coche blanche sur le sceau bleu, quel que soit le fond', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Center(child: BadgePremium(taille: 40)))));
    final sceau = t.widget<Icon>(find.byIcon(Icons.verified));
    expect(sceau.color, bleuBadgePremium);
    final disque = t.widget<Container>(find.descendant(of: find.byType(BadgePremium), matching: find.byType(Container)));
    expect((disque.decoration as BoxDecoration).color, Colors.white);
  });
}
