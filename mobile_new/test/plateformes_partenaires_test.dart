import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/abonnement/domain/tarifs_premium.dart';

/// Aucune phrase ne promet une enseigne que le sélecteur n'offre pas.
///
/// ── Le défaut ─────────────────────────────────────────────────────────────
///
/// Le parcours « code promo » proposait trois enseignes. La liste était
/// publiée par le serveur — donc modifiable — mais **trois phrases de l'écran
/// les nommaient en toutes lettres** :
///
///   - « Crée un compte sur 1xBet, Melbet ou Betwinner avec notre code » ;
///   - « Rendez-vous sur 1xBet, Melbet ou Betwinner » ;
///   - « Tu crées un compte sur une plateforme partenaire (1xBet, Melbet,
///     Betwinner) ».
///
/// Réduire le partenariat à 1xBet côté serveur aurait donc retiré deux
/// pastilles du sélecteur en continuant de promettre les deux enseignes trois
/// lignes plus haut. L'utilisateur aurait ouvert un compte Melbet, fait son
/// dépôt, envoyé sa capture — et réclamé un mois offert que rien ne justifie.
///
/// C'est le défaut déjà corrigé pour les opérateurs Mobile Money, dont le
/// commentaire de `libelleOperateurs` garde la trace : « L'écran d'accroche
/// annonçait quatre opérateurs en dur pendant que le serveur n'en publiait
/// qu'un ». Le même, un étage plus loin.
void main() {
  TarifsPremium avec(List<String> plateformes) =>
      TarifsPremium.depuis({'betting_platforms': plateformes});

  group('la phrase suit la liste publiée', () {
    test('une seule enseigne se nomme seule', () {
      expect(avec(['1xbet']).libellePlateformes, '1xBet');
    });

    test('deux enseignes se joignent par « ou »', () {
      expect(avec(['1xbet', 'melbet']).libellePlateformes, '1xBet ou Melbet');
    });

    test('trois enseignes gardent la virgule avant le « ou »', () {
      expect(avec(['1xbet', 'melbet', 'betwinner']).libellePlateformes,
          '1xBet, Melbet ou Betwinner');
    });

    test('une enseigne inconnue est nommée, pas cachée', () {
      // Le serveur peut publier une clé que cette version ne connaît pas. La
      // taire donnerait une phrase qui annonce moins que le sélecteur.
      expect(avec(['1xbet', 'nouvelle']).libellePlateformes,
          '1xBet ou Nouvelle');
    });

    test('aucune enseigne donne une chaîne vide, pas « null »', () {
      expect(avec([]).libellePlateformes, '');
    });
  });

  group('le sélecteur ne demande pas de choisir sans choix', () {
    test('une seule enseigne : pas de sélecteur', () {
      expect(avec(['1xbet']).plusieursPlateformes, isFalse);
    });

    test('deux enseignes : un sélecteur', () {
      expect(avec(['1xbet', 'melbet']).plusieursPlateformes, isTrue);
    });
  });

  group('le partenariat en vigueur', () {
    test('le repli hors ligne ne propose que 1xBet', () {
      // Sans réponse du serveur, l'écran ne doit pas ressusciter d'anciennes
      // enseignes : ce sont des comptes que l'utilisateur ouvrirait pour rien.
      expect(TarifsPremium.plateformesDefaut, ['1xbet']);
      expect(TarifsPremium.depuis(null).libellePlateformes, '1xBet');
    });
  });

  group('aucun écran ne nomme une enseigne à la main', () {
    /// Le code seul : les commentaires citent « Melbet » et « Betwinner » pour
    /// expliquer ce qui a été retiré, et cette explication doit rester lisible.
    String codeSeul(String source) => source
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
        })
        .join('\n');

    test('hors de la carte de noms, aucune enseigne n\'est écrite', () {
      final fautifs = <String>[];

      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final chemin = f.path.replaceAll(r'\', '/');

        // `tarifs_premium.dart` porte la carte qui *nomme* les clés. C'est sa
        // raison d'être : elle traduit une clé publiée, elle ne décide pas
        // laquelle l'est.
        if (chemin.endsWith('domain/tarifs_premium.dart')) continue;

        final code = codeSeul(f.readAsStringSync());
        for (final enseigne in ['Melbet', 'Betwinner', 'melbet', 'betwinner']) {
          if (code.contains(enseigne)) fautifs.add('$chemin nomme $enseigne');
        }
      }

      expect(fautifs, isEmpty,
          reason: 'une enseigne écrite à la main survit au retrait de la '
              'liste publiée :\n${fautifs.join('\n')}');
    });

    test('et les textes passent bien par le libellé dérivé', () {
      // Le contre-test du précédent : supprimer les mentions sans les
      // remplacer donnerait une page verte et un écran muet.
      //
      // Le contrôle exigeait **trois** emplois — le nombre de phrases qui
      // citaient les enseignes à l'époque. Ce n'était pas la propriété, juste
      // son décompte du jour : réduire le parcours de cinq étapes à trois en a
      // supprimé une, et le test est tombé sans qu'aucune enseigne ne soit
      // revenue en dur.
      //
      // Ce qui doit être tenu, c'est qu'aucun nom d'enseigne ne soit écrit à
      // la main — et c'est l'objet du test précédent, qui relit tout `lib/`.
      // Ici on vérifie seulement que l'écran s'en sert réellement.
      final ecran = File(
        'lib/features/abonnement/presentation/pages/activer_premium_page.dart',
      ).readAsStringSync();

      expect(ecran, contains('libellePlateformes'),
          reason: "l'écran doit nommer l'enseigne d'après la liste publiée");
    });
  });
}
