import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/bookmaker_affiliation.dart';
import 'package:pronowin/core/theme/app_theme.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail/bookmaker_cotes.dart';

Widget _hote(Widget enfant) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SingleChildScrollView(child: enfant)),
    );

void main() {
  group('Lien d\'affiliation — une erreur ici ne se voit pas', () {
    // Ce groupe verifiait que le lien etait exactement celui du compte
    // partenaire, tag compris. C'etait la bonne garde pour l'ancien dessin :
    // le lien vivait dans le binaire.
    //
    // Il vient desormais du serveur, parce qu'un lien d'affiliation expire
    // sans prevenir et que le remplacer ne doit pas demander de republier
    // l'application. Ce qu'il faut garder a change de nature : plus la valeur,
    // mais le fait qu'aucune valeur ne soit ecrite en dur, et qu'un lien
    // absent n'ouvre rien.

    setUp(() => BookmakerAffiliation.configurer(null));

    test('sans configuration, aucun partenariat n est propose', () {
      expect(BookmakerAffiliation.disponible, isFalse);
      expect(BookmakerAffiliation.lien, isEmpty);
      expect(BookmakerAffiliation.nom,  isEmpty);
    });

    test('le lien publie par le serveur est repris tel quel', () {
      // Tag, identifiant de compte et creatif doivent traverser intacts : un
      // caractere de travers ne casse rien a l ecran, et seuls les releves de
      // commission le revelent, des semaines plus tard.
      const lien = 'https://reffpa.com/L?tag=d_1793663m_97c_&site=1793663&ad=97';
      BookmakerAffiliation.configurer(
        {'affiliateUrl': lien, 'affiliateName': '1xBet'});

      expect(BookmakerAffiliation.lien, lien);
      expect(BookmakerAffiliation.nom, '1xBet');
      expect(BookmakerAffiliation.disponible, isTrue);

      final uri = Uri.parse(BookmakerAffiliation.lien);
      expect(uri.queryParameters['tag'],  'd_1793663m_97c_');
      expect(uri.queryParameters['site'], '1793663');
      expect(uri.queryParameters['ad'],   '97');
    });

    test('une URL qui n en est pas une est refusee', () {
      // Un champ mal saisi dans l administration ne doit pas produire un
      // bouton qui ouvre n importe quoi.
      for (final mauvais in ['reffpa.com/L', 'javascript:alert(1)', '   ', '']) {
        BookmakerAffiliation.configurer({'affiliateUrl': mauvais});
        expect(BookmakerAffiliation.disponible, isFalse, reason: mauvais);
      }
    });

    test('aucun lien d affiliation n est ecrit dans le binaire', () {
      // Le commentaire de ce fichier ne cite pas le domaine du partenaire :
      // la lecture brute suffit, sans filtrer les commentaires.
      final source = File('lib/core/config/bookmaker_affiliation.dart')
          .readAsStringSync();

      expect(source.contains('reffpa.com'), isFalse);
    });

    test('un seul chemin ouvre le partenaire', () {
      // `miser_dialog` avait sa propre copie de `launchUrl` — celle-la meme que
      // le commentaire de la classe redoutait. Elle ignorait le garde
      // « aucun partenariat configure ».
      final dialogue = File('lib/features/bankroll/presentation/widgets/'
                            'miser_dialog.dart').readAsStringSync();

      expect(dialogue.contains('launchUrl('), isFalse);
      expect(dialogue, contains('BookmakerAffiliation.ouvrir()'));
    });
  });

  group('BookmakerCotes', () {
    // Le bandeau ne s'affiche plus sans partenariat configuré : il annoncerait
    // une enseigne au nom vide et mènerait à une ouverture qui ne se produit
    // pas. Ces tests dépendaient jusqu'ici d'un affichage inconditionnel — ils
    // configurent donc un partenariat, comme en production.
    setUp(() => BookmakerAffiliation.configurer({
          'affiliateUrl':  'https://exemple.test/L?tag=t&site=1&ad=1',
          'affiliateName': 'Partenaire',
        }));
    tearDown(() => BookmakerAffiliation.configurer(null));

    testWidgets('sans partenariat configuré, le bandeau disparaît',
        (tester) async {
      // Le défaut qui a motivé ce garde : `disponible` était déclaré et aucun
      // écran ne l'appelait. Le bouton s'affichait, se laissait presser, et ne
      // faisait rien.
      BookmakerAffiliation.configurer(null);

      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.85, coteNul: 3.40, coteExterieur: 4.20)));

      expect(find.text('1.85'), findsNothing);
      expect(find.textContaining('Publicit'), findsNothing);
    });

    testWidgets('sans aucune cote, rien ne s\'affiche', (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 0, coteNul: 0, coteExterieur: 0)));

      // Une marque de bookmaker au-dessus de trois tirets serait une publicité
      // déguisée en information.
      expect(find.textContaining('18+'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('les trois cotes sont affichées avec deux décimales',
        (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 3.7, coteExterieur: 4.45)));

      expect(find.text('1.65'), findsOneWidget);
      expect(find.text('3.70'), findsOneWidget,
          reason: '3.7 doit se lire 3.70, comme chez le bookmaker');
      expect(find.text('4.45'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('la tuile du logo garde un fond clair', (tester) async {
      // Le créatif officiel est un « 1X » bleu marine (#0A2A5E) sur
      // transparence. Reposer la tuile sur un fond sombre — ce qu'elle faisait
      // — ferait littéralement disparaître la moitié du logo, sans qu'aucune
      // erreur ne se produise : l'image se charge, elle est simplement
      // invisible.
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 3.7, coteExterieur: 4.45)));

      final tuile = tester.widget<Container>(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(Container),
        ).first,
      );
      final fond = (tuile.decoration as BoxDecoration).color!;

      // Luminance perçue : bien au-dessus du marine du lettrage.
      expect(fond.computeLuminance(), greaterThan(0.5),
          reason: 'un fond sombre masquerait le « 1X » du logo');
    });

    testWidgets('la mention légale accompagne toujours les cotes',
        (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 3.7, coteExterieur: 4.45)));

      // Elle n'est pas optionnelle : une promotion de paris sans « 18+ »
      // expose l'app à un retrait des stores.
      expect(find.textContaining('18+'), findsOneWidget);
      expect(find.textContaining('Publicité'), findsOneWidget);
    });

    testWidgets('une cote manquante affiche un tiret et ne réagit pas au tap',
        (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 0, coteExterieur: 4.45)));

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0.00'), findsNothing,
          reason: 'une cote absente n\'est pas une cote à zéro');

      // Trois pastilles, mais seulement deux sont actionnables.
      final actifs = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((w) => w.onTap != null);
      expect(actifs.length, 2);
    });

    testWidgets('la cote du pronostic est mise en évidence', (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 3.7, coteExterieur: 4.45,
        indiceRecommande: 2)));

      final marques = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.color == AppColors.success)
          .map((t) => t.data)
          .toList();
      expect(marques, contains('4.45'));
      expect(marques, isNot(contains('1.65')));
    });

    testWidgets('les cotes portent un libellé lisible par un lecteur d\'écran',
        (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 3.7, coteExterieur: 4.45)));

      // Le libellé annonce la conséquence — quitter l'app — et pas seulement
      // la valeur affichée.
      expect(
        find.bySemanticsLabel(
            'Cote 1, 1.65 — parier sur ${BookmakerAffiliation.nom}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Cote X, 3.70 — parier sur ${BookmakerAffiliation.nom}'),
        findsOneWidget,
      );
    });




    testWidgets('une cote absente n\'est pas annoncée comme un bouton',
        (tester) async {
      await tester.pumpWidget(_hote(const BookmakerCotes(
        coteDomicile: 1.65, coteNul: 0, coteExterieur: 4.45)));

      expect(find.bySemanticsLabel('Cote X indisponible'), findsOneWidget);

      final boutons = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.button == true);
      expect(boutons.length, 2,
          reason: 'seules les cotes réellement actionnables sont des boutons');
    });
  });
}
