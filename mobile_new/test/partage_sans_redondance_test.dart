import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/constants/app_constants.dart';
import 'package:pronowin/shared/utils/partage_parrainage.dart';

/// Ce qu'on écrit à côté d'une image, et où mène le lien.
///
/// ── Le texte répétait l'image, ligne pour ligne ───────────────────────────
///
/// Le message de partage portait les équipes, la compétition, la date, le
/// pronostic, la confiance et la cote. La carte partagée juste au-dessus porte
/// **exactement les mêmes** : la ligue en pastille, les écussons avec les noms,
/// le pronostic en grand, la cote et la confiance en encadrés, la date et le
/// domaine en pied. Pour un match joué, elle affiche même le score et un
/// bandeau « Pronostic GAGNANT ».
///
/// Le destinataire lisait tout en double, et le lien — la seule chose qu'une
/// image ne peut pas porter — arrivait en huitième ligne.
///
/// ── Et le lien de téléchargement ne menait nulle part ─────────────────────
///
/// Les messages de parrainage écrivaient `pronowin.com/download`. Trois
/// défauts dans une ligne : le domaine n'est pas le nôtre (`.space`), le
/// chemin répond 404 sur le vrai site, et sans schéma aucune messagerie n'en
/// fait un lien cliquable.
///
/// Elle était recopiée à la main dans deux écrans — l'onglet Compte et la page
/// Parrainage — dont l'un disait en commentaire « identique à celui de
/// ParrainagePage ». Deux copies d'une même phrase vieillissent ensemble.
void main() {
  group("l'adresse de téléchargement", () {
    test('est absolue et sur le bon domaine', () {
      expect(AppConstants.apkDownloadUrl, startsWith('https://'));
      expect(AppConstants.apkDownloadUrl, contains('pronowin.space'));
      expect(AppConstants.apkDownloadUrl, endsWith('.apk'));
    });

    test('ne porte plus l\'ancien domaine ni l\'ancien chemin', () {
      expect(AppConstants.apkDownloadUrl, isNot(contains('pronowin.com')));
      expect(AppConstants.apkDownloadUrl, isNot(endsWith('/download')));
    });

    test('dérive du domaine, elle ne le réécrit pas', () {
      // Sans cela, changer `domaine` laisserait cette adresse en arrière —
      // exactement ce qui s'est produit avec `pronowin.com`.
      expect(AppConstants.apkDownloadUrl, startsWith(AppConstants.siteUrl));
    });
  });

  group('le message de parrainage', () {
    test('porte un lien cliquable vers le vrai fichier', () {
      final m = messageParrainage('ABC123');
      expect(m, contains(AppConstants.apkDownloadUrl));
      expect(m, isNot(contains('pronowin.com')));
    });

    test('porte le code du parrain', () {
      expect(messageParrainage('ABC123'), contains('ABC123'));
    });

    test('vit à un seul endroit', () {
      // Contrôle textuel : deux copies recopiées à la main sont exactement ce
      // qui a laissé la mauvaise adresse survivre.
      final ecrans = [
        'lib/features/compte/presentation/pages/compte_page.dart',
        'lib/features/parrainage/presentation/pages/parrainage_page.dart',
      ];
      for (final chemin in ecrans) {
        final source = File(chemin).readAsStringSync();
        expect(source, contains('messageParrainage('),
            reason: '$chemin doit passer par la source unique');
        expect(source.contains('Rejoins PronoWin et gagne avec'), isFalse,
            reason: '$chemin porte de nouveau sa propre copie du message');
      }
    });
  });

  group("le texte de partage n'est plus le double de l'image", () {
    late String partage;

    setUpAll(() {
      partage = File(
        'lib/features/pronostics/presentation/pages/match_detail/partage.dart',
      ).readAsStringSync();
    });

    /// Le code seul : les commentaires citent l'ancien message pour expliquer
    /// ce qui a été retiré, et cette explication doit rester lisible.
    String codeSeul(String s) => s
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
        })
        .join('\n');

    test('il ne répète plus ce que la carte affiche', () {
      final code = codeSeul(partage);
      for (final champ in [
        'match.league',              // la pastille de ligue
        'confidencePercent',         // l'encadré Confiance
        'oddsRecommended',           // l'encadré Cote
        'displayPredictionLabel',    // le pronostic en grand
        'homeScore',                 // le score, quand le match est joué
      ]) {
        expect(code, isNot(contains(champ)),
            reason: '« $champ » figure déjà sur la carte partagée');
      }
    });

    test('il ne porte plus le lien de détail, qui était mort', () {
      // `pronowin.space/pronostics/<id>` n'existe pas : le site ne sert que
      // l'accueil et les pages légales, et toute adresse sous `/pronostics`
      // répond 404 — vérifié sur le serveur avec l'identifiant réel d'un
      // pronostic partagé. Chaque partage envoyait donc le destinataire sur
      // une erreur, et c'est l'application qu'il jugeait.
      final code = codeSeul(partage);
      expect(code, isNot(contains('/pronostics/')),
          reason: 'cette route n\'existe pas sur le site');
    });

    test('il garde le seul lien qui mène quelque part', () {
      expect(partage, contains('AppConstants.apkDownloadUrl'));
    });

    test('il dit où trouver le détail', () {
      // Retirer le lien sans rien mettre à la place laisserait le lecteur
      // sans réponse à la question que l'image lui pose.
      expect(partage, contains('consulter le détail'));
    });

    test('il garde une ligne de sujet', () {
      // Contrepartie assumée : un message qui n'annoncerait que des liens se
      // lit comme un envoi douteux, et certains clients n'affichent pas les
      // images. Les équipes sont la seule répétition retenue.
      final code = codeSeul(partage);
      expect(code, contains('match.homeTeam'));
      expect(code, contains('match.awayTeam'));
    });

    test('il distingue encore un pronostic gagné d\'un pronostic à venir', () {
      // Le résultat est la raison même de partager : le taire ramènerait le
      // défaut que le message d'origine avait déjà dû corriger une fois.
      final code = codeSeul(partage);
      expect(code, contains('PronosticResult.win'));
      expect(code, contains('PronosticResult.loss'));
      expect(code, contains('PronosticResult.push'));
    });
  });
}
