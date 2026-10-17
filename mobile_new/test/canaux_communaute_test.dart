import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/widgets/comments_section.dart';
import 'aides/banc_ecran.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/contact_support.dart';

void main() {
  setUpAll(preparerBanc);
  for (final nombre in [0, 1, 3]) {
    testWidgets('canaux visibles avec $nombre commentaires', (tester) async {
      final result = await mesurerEcran(tester,
        ecran: const Scaffold(body: SingleChildScrollView(child: CommentsSection(pronosticId: 'm'))),
        theme: AppTheme.light, echelle: 1,
        surcharges: [commentsProvider('m').overrideWith((ref) async => CommentsData(
          vote: const PronosticVoteData(agree: 0, disagree: 0, total: 0),
          comments: List.generate(nombre, (i) => PronosticComment(id: '$i', userId: 'autre',
            content: 'Mon avis $i', isExpert: false, createdAt: DateTime(2026, 10, 11), userPseudo: 'Membre'))))],
        verifier: () {
          expect(find.text('Telegram'), findsOneWidget);
          expect(find.text('WhatsApp'), findsOneWidget);
          if (nombre > 0) expect(find.text('Mon avis 0'), findsOneWidget);
        });
      expect(result.autres, isEmpty);
      expect(result.debordements, isEmpty);
    });
  }

  final section = File(
    'lib/features/pronostics/presentation/widgets/comments_section.dart',
  ).readAsStringSync();

  final code = section
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');

  test('les canaux sont regroupés en un seul endroit', () {
    expect(ContactSupport.telegram.isNotEmpty, isTrue);
    expect(ContactSupport.whatsapp.isNotEmpty, isTrue);
    // Un lien recopié dans un écran finit par diverger de l'autre.
    expect(code.contains('whatsapp.com/channel'), isFalse,
      reason: 'le lien appartient à ContactSupport, pas à l\'écran');
    expect(code.contains('t.me/'), isFalse);
  });

  test('les canaux vivent dans un seul widget, hors des deux verrous', () {
    final debut = code.indexOf('class _CanauxCommunaute');
    expect(debut, greaterThan(-1), reason: 'le bloc doit être extrait');

    // Les liens ne sont ouverts que depuis ce widget. S'ils réapparaissaient
    // dans `_EmptyComments`, l'utilisateur Premium les verrait deux fois ; s'ils
    // étaient posés dans `_CommentsPremiumLocked` ou `_CommentsGuestLocked`,
    // ils se disputeraient le tap avec la surface cliquable de ces cartes.
    final avant = code.substring(0, debut);
    expect(avant.contains('ouvrirTelegram'), isFalse);
    expect(avant.contains('ouvrirWhatsapp'), isFalse);

    for (final verrou in ['_CommentsPremiumLockedState', '_CommentsGuestLocked']) {
      final d = code.indexOf('class $verrou');
      expect(d, greaterThan(-1), reason: '$verrou doit exister');
      final fin = code.indexOf('\nclass ', d + 1);
      final corps = code.substring(d, fin == -1 ? code.length : fin);
      expect(corps.contains('ouvrirTelegram'), isFalse,
        reason: '$verrou capte le tap sur toute sa surface');
    }
  });

  test('quitter l\'application est annoncé', () {
    final d = code.indexOf('class _BoutonCanal');
    expect(d, greaterThan(-1));
    final corps = code.substring(d);
    expect(corps.contains('Semantics('), isTrue);
    expect(corps.contains('tr(context, "Rejoindre le canal {arg0} — ouvre {arg1}", [libelle, libelle])'), isTrue,
      reason: 'un lecteur d\'écran doit savoir que le bouton bascule vers une '
              'autre application');
  });
}
