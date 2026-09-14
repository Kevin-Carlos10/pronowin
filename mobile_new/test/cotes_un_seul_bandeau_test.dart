import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/pronostics/presentation/pages/match_detail/bookmaker_cotes.dart';

/// Un seul bandeau de cotes, jamais deux — et jamais aucun.
///
/// L'onglet « Cotes » empilait les deux : les mêmes trois valeurs, à quarante
/// pixels d'écart, l'une en lecture seule et l'autre cliquable. La raison était
/// bonne — un appui de travers ne doit pas faire quitter l'application — mais à
/// l'écran cela se lisait comme un défaut d'affichage.
///
/// Et le bandeau du haut portait les cotes du **même** bookmaker sans son logo
/// ni la mention « 18+ » : des cotes commerciales présentées comme une donnée
/// neutre.
///
/// ── Ce que ce banc empêche surtout ─────────────────────────────────────────
///
/// Supprimer le bandeau neutre sans condition aurait vidé l'onglet « Cotes »
/// pour les utilisateurs des boutiques — le bandeau du partenaire n'y est pas
/// publié — et pour tous, le jour où aucun partenariat n'est configuré. Un
/// onglet nommé « Cotes » qui n'affiche aucune cote et n'explique rien est le
/// défaut que ce dépôt corrige depuis des semaines.
void main() {
  group('quel bandeau afficher', () {
    test('canal direct, partenaire configuré : celui du partenaire', () {
      expect(
        bandeauCotes(estStore: false, partenaireDisponible: true),
        BandeauCotes.partenaire,
      );
    });

    test('paquet des boutiques : le neutre', () {
      // Un lien d'affiliation cliquable vers un opérateur de paris est le motif
      // de retrait le plus direct. Les cotes, elles, restent affichées.
      expect(
        bandeauCotes(estStore: true, partenaireDisponible: true),
        BandeauCotes.neutre,
      );
    });

    test('aucun partenariat configuré : le neutre, même en direct', () {
      // Une marque posée au-dessus de trois tirets serait une publicité
      // déguisée en information ; l'absence de bandeau serait un onglet vide.
      expect(
        bandeauCotes(estStore: false, partenaireDisponible: false),
        BandeauCotes.neutre,
      );
    });

    test('jamais rien : les deux cas restants donnent le neutre', () {
      // Contrepartie : une règle qui rendrait « partenaire » partout, ou qui
      // n'aurait aucune valeur de repli, passerait les contrôles ci-dessus
      // sans les couvrir tous.
      expect(
        bandeauCotes(estStore: true, partenaireDisponible: false),
        BandeauCotes.neutre,
      );
      for (final estStore in [true, false]) {
        for (final dispo in [true, false]) {
          expect(
            bandeauCotes(estStore: estStore, partenaireDisponible: dispo),
            isNotNull,
          );
        }
      }
    });
  });

  group('la carte des cotes applique la règle', () {
    final source = File(
      'lib/features/pronostics/presentation/pages/match_detail_page.dart',
    ).readAsStringSync();

    test('elle interroge la règle plutôt que le canal directement', () {
      expect(source, contains('bandeauCotes('),
          reason: 'la décision doit passer par la règle éprouvée ci-dessus');
      expect(source, contains('BookmakerAffiliation.disponible'),
          reason: 'sans partenariat configuré, le bandeau du partenaire ne '
                  'peut pas s\'afficher — il faut donc le savoir avant de '
                  'supprimer le neutre');
    });

    test('les deux bandeaux s\'excluent', () {
      // C'est tout l'objet du changement : l'un OU l'autre, jamais empilés.
      final carte = source.substring(source.indexOf('class _OddsCard'));
      final decision = carte.indexOf('bandeauCotes(');
      final partenaire = carte.indexOf('BookmakerCotes(', decision);
      final sinon = carte.indexOf('      else', decision);

      expect(decision, greaterThan(-1));
      expect(partenaire, greaterThan(decision));
      expect(sinon, greaterThan(partenaire),
          reason: 'le bandeau neutre doit être la branche « sinon » du '
                  'partenaire, pas un bloc affiché en plus');
    });

    test('le marché reste nommé dans les deux cas', () {
      // « COTES » seul laissait croire que ces trois valeurs étaient celles du
      // pronostic. La mention avait été ajoutée au bandeau neutre ; elle aurait
      // disparu du canal direct avec lui.
      expect(source, contains("const marche = 'VAINQUEUR DU MATCH'"));
      expect(source, contains('marche:        marche,'),
          reason: 'le bandeau du partenaire doit recevoir le nom du marché');

      final widget = File(
        'lib/features/pronostics/presentation/pages/match_detail/'
        'bookmaker_cotes.dart',
      ).readAsStringSync();
      expect(widget, contains('final String? marche;'));
      expect(widget, contains('if (marche != null)'),
          reason: 'le bandeau doit rendre le nom du marché quand il le reçoit');
    });

    test('la cote recommandée se repère dans les deux cas', () {
      // Le repère vert ne vaut que si le pronostic porte sur le 1X2 : sur un
      // « Total buts », les trois cotes sont sans rapport avec lui.
      expect(source, contains('indiceRecommande: indiceRecommande'));
      expect(source, contains('isRecommended: indiceRecommande == 0'));
      expect(source, contains('PredictionType.win1  => 0'));
      expect(source, contains('=> null'),
          reason: 'hors 1X2, aucune cote ne doit être repérée : sur un '
                  '« Total buts », les trois cotes 1/X/2 sont sans rapport '
                  'avec le pronostic');
    });
  });
}
