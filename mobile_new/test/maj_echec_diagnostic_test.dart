import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/services/installateur_maj.dart';
import 'package:pronowin/core/widgets/ecran_mise_a_jour.dart';

/// Ce que l'écran dit quand la mise à jour échoue.
///
/// ── Ce qui s'est passé ────────────────────────────────────────────────────
///
/// Un utilisateur bloqué par une mise à jour obligatoire a vu cinq fois :
/// « Téléchargement interrompu. Vérifiez votre connexion. »
///
/// Les journaux du serveur, aux mêmes minutes, montrent cinq requêtes en
/// `200` avec **71 120 949 octets envoyés à chaque fois** — le fichier entier.
/// Le réseau n'avait rien interrompu. L'application l'accusait faute de savoir
/// dire autre chose : une `DioException` et un `catch (e)` attrapant tout le
/// reste menaient au même texte, et rien n'était journalisé. La cause était
/// jetée avant d'avoir été lue.
///
/// ── Pourquoi c'est grave ici, et pas ailleurs ─────────────────────────────
///
/// Cet écran est sans issue quand la mise à jour est obligatoire : ni retour,
/// ni « Plus tard ». Le diagnostic affiché est donc la seule prise que
/// l'utilisateur ait sur son problème. S'il est faux, il l'envoie chercher une
/// panne qui n'existe pas pendant que la vraie reste invisible.
///
/// Et « Réessayer » relance exactement ce qui vient d'échouer. Sans seconde
/// voie, la boucle est fermée — c'est ce qu'a vécu cet utilisateur.
void main() {
  Future<void> ouvrir(
    WidgetTester tester, {
    required Object erreur,
    bool bloquant = true,
    String lien = 'https://pronowin.space/downloads/app-release.apk',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EcranMiseAJour(
        message: 'Une nouvelle version est disponible.',
        bloquant: bloquant,
        lien: lien,
        installationDirecte: true,
        telechargeur: (url, {required progression, annulation}) async =>
            throw erreur,
      ),
    ));
    await tester.tap(find.byKey(const Key('maj-action')));
    await tester.pumpAndSettle();
  }

  String messageAffiche(WidgetTester tester) {
    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((d) => d.isNotEmpty);
    return textes.join(' | ');
  }

  group('le classement des causes', () {
    test('un disque plein n\'est pas une panne réseau', () {
      expect(
        InstallateurMaj.raisonDe(
            const FileSystemException('write failed', '', OSError('ENOSPC', 28))),
        RaisonEchec.espace);
    });

    test('une écriture enveloppée par Dio est reconnue quand même', () {
      // C'est le cas réel : Dio range l'erreur d'écriture sous `unknown`. S'en
      // tenir au type ferait passer un disque plein pour un incident réseau.
      expect(
        InstallateurMaj.raisonDe(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.unknown,
          error: const FileSystemException('no space left'),
        )),
        RaisonEchec.espace);
    });

    test('une vraie coupure réseau est bien du réseau', () {
      expect(
        InstallateurMaj.raisonDe(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        )),
        RaisonEchec.reseau);
    });

    test('un 404 accuse le serveur, pas la connexion de l\'utilisateur', () {
      expect(
        InstallateurMaj.raisonDe(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: '/x'), statusCode: 404),
        )),
        RaisonEchec.serveur);
    });

    test('ce qu\'on ne sait pas est dit inconnu, pas déguisé', () {
      // `inconnu` est une réponse acceptable. Inventer une panne réseau ne
      // l'est pas : c'est ce qui a rendu le vrai défaut introuvable.
      expect(InstallateurMaj.raisonDe(StateError('quelque chose')),
          RaisonEchec.inconnu);
    });
  });

  group('ce que l\'écran affiche', () {
    testWidgets('un disque plein ne parle plus de connexion', (tester) async {
      await ouvrir(tester,
          erreur: const EchecTelechargement(RaisonEchec.espace));

      final texte = messageAffiche(tester);
      expect(texte, contains('Espace insuffisant'));
      expect(texte, isNot(contains('Vérifiez votre connexion')),
          reason: 'l\'utilisateur irait vérifier une connexion qui marche');
    });

    testWidgets('une vraie coupure réseau le dit toujours', (tester) async {
      // Le contre-test : corriger le message ne doit pas le supprimer là où il
      // était juste.
      await ouvrir(tester,
          erreur: const EchecTelechargement(RaisonEchec.reseau));

      expect(messageAffiche(tester), contains('Vérifiez votre connexion'));
    });

    testWidgets('un serveur indisponible n\'accuse pas l\'utilisateur',
        (tester) async {
      await ouvrir(tester,
          erreur: const EchecTelechargement(RaisonEchec.serveur));

      final texte = messageAffiche(tester);
      expect(texte, contains('pas disponible'));
      expect(texte, isNot(contains('Vérifiez votre connexion')));
    });
  });

  group('la boucle fermée est ouverte', () {
    final navigateur = find.byKey(const Key('maj-navigateur'));

    testWidgets('après un échec, une seconde voie est proposée',
        (tester) async {
      await ouvrir(tester,
          erreur: const EchecTelechargement(RaisonEchec.inconnu));

      expect(navigateur, findsOneWidget,
          reason: '« Réessayer » relance ce qui vient d\'échouer ; sur un '
              'écran bloquant, l\'utilisateur n\'a alors plus aucune issue');
    });

    testWidgets('elle mène au navigateur, qui sait reprendre', (tester) async {
      Uri? demande;
      await tester.pumpWidget(MaterialApp(
        home: EcranMiseAJour(
          message: 'Une nouvelle version est disponible.',
          bloquant: true,
          lien: 'https://pronowin.space/downloads/app-release.apk',
          installationDirecte: true,
          telechargeur: (url, {required progression, annulation}) async =>
              throw const EchecTelechargement(RaisonEchec.inconnu),
          ouvreur: (u) async { demande = u; return true; },
        ),
      ));
      await tester.tap(find.byKey(const Key('maj-action')));
      await tester.pumpAndSettle();
      await tester.tap(navigateur);
      await tester.pumpAndSettle();

      expect(demande.toString(),
          'https://pronowin.space/downloads/app-release.apk');
    });

    testWidgets('elle n\'apparaît pas tant que rien n\'a échoué',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EcranMiseAJour(
          message: 'Une nouvelle version est disponible.',
          bloquant: true,
          lien: 'https://pronowin.space/downloads/app-release.apk',
          installationDirecte: true,
        ),
      ));
      await tester.pump();

      expect(navigateur, findsNothing);
    });
  });
}
