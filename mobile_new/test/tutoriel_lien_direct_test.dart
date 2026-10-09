import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'aides/code_seul.dart';

/// Un lien vers un tutoriel doit ouvrir ce tutoriel.
///
/// ── U4 : « Tutoriel introuvable » sur un tutoriel qui existe ──────────────
///
/// La page ne lisait que `widget.preloaded`, c'est-à-dire l'objet Dart passé
/// en `extra` par la liste. Un lien partagé, une notification, une reprise
/// après redémarrage — rien de cela ne transporte un objet Dart. La page
/// affichait donc « Tutoriel introuvable » alors que le tutoriel existait, et
/// que `tutorialDetailProvider` était là, inutilisé.
///
/// ── U5 : une réussite annoncée sans confirmation ──────────────────────────
///
/// « Terminé » posait l'état local, appelait le réseau dans un `try` dont le
/// `catch` ne faisait rien, et affichait « Tutoriel marqué comme terminé ! »
/// dans tous les cas. Le résultat `Either` de l'enregistrement était jeté. Au
/// lancement suivant, la coche avait disparu sans explication.
///
/// Ces contrôles sont textuels : ni le compilateur ni l'analyseur ne voient
/// une page qui n'appelle pas le provider dont elle dispose.
void main() {
  late String page;
  late String provider;

  setUpAll(() {
    String lire(String chemin) {
      final f = File(chemin);
      if (!f.existsSync()) fail('Fichier introuvable : $chemin');
      return f.readAsStringSync().pipeCodeSeul();
    }

    page = lire(
        'lib/features/tutoriels/presentation/pages/tutorial_detail_page.dart');
    provider = lire(
        'lib/features/tutoriels/presentation/providers/tutorial_provider.dart');
  });

  group('la page se charge par identifiant', () {
    test('elle consulte le provider de détail', () {
      expect(page, contains('tutorialDetailProvider(widget.tutorialId)'));
    });

    test('elle distingue chargement, erreur et contenu', () {
      // « Introuvable » servait pour les trois. Le plus souvent, c'est la
      // connexion qui manque — pas le tutoriel.
      expect(page, contains('loading:'));
      expect(page, contains('error:'));
      expect(page.contains("Text('Tutoriel introuvable'"), isFalse,
          reason: 'ce message désignait le tutoriel pour un défaut de réseau');
    });

    test('elle propose de réessayer', () {
      expect(page, contains("Key('tutoriel-reessayer')"));
      expect(page, contains('ref.invalidate(tutorialDetailProvider'));
    });

    test('le préchargement reste un raccourci, pas une condition', () {
      // Contrepartie : ouvrir depuis la liste ne doit pas déclencher un
      // aller-retour réseau inutile.
      expect(page, contains('if (precharge != null) return _contenu'));
    });
  });

  group("l'enregistrement de la progression est vérifié", () {
    test('le provider rend le résultat au lieu de le jeter', () {
      expect(provider, contains('Future<bool> updateProgress'));
      expect(provider, contains('r.isRight()'));
    });

    test('le message dépend de ce que le serveur a répondu', () {
      // La clé est choisie à l'exécution — on cherche donc les deux valeurs,
      // pas un `Key('…')` littéral.
      expect(page, contains("'tutoriel-termine'"));
      expect(page, contains("'tutoriel-non-enregistre'"));
      expect(page, contains('Progression non enregistrée'));
    });

    test('un enregistrement réussi rafraîchit la liste', () {
      // Sans invalidation, la liste continuait d'afficher le tutoriel comme
      // non fait jusqu'au prochain démarrage.
      expect(page, contains('ref.invalidate(tutorialsProvider)'));
    });

    test('le catch ne se contente plus de ne rien faire', () {
      expect(page.contains(
              "// Ignorer les erreurs réseau silencieusement"),
          isFalse);
    });
  });

  group('le verrou Premium regarde le lecteur', () {
    test('il croise le tutoriel et l\'abonnement', () {
      // `isPremiumLocked = t.isPremium` refusait à un abonné un contenu qu'il
      // a payé. Latent tant que tout est gratuit — et ce jour-là, personne ne
      // pensera à cette ligne.
      expect(page, contains('t.isPremium && !lecteurPremium'));
      expect(page.contains('final isPremiumLocked = t.isPremium;'), isFalse);
    });
  });
}
