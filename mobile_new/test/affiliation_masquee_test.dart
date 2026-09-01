import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Aucune invitation à parier quand aucun partenariat n'est configuré.
///
/// `BookmakerAffiliation.disponible` existait — et **aucun fichier ne
/// l'appelait**. Le garde vivait dans `ouvrir()`, qui sort en silence : le
/// bouton « Aller miser sur 1xBet » s'affichait, se laissait presser, et ne
/// faisait rien. Juste après la confirmation d'une mise.
///
/// C'est mot pour mot ce que le commentaire de la classe redoutait : « un lien
/// mort fait cliquer sans rien rapporter, et il use la confiance au passage ».
/// Il le redoutait au niveau de l'ouverture ; personne ne l'avait branché au
/// niveau de l'affichage.
///
/// Deuxième défaut au même endroit : le bouton écrivait « 1xBet » en dur alors
/// que le serveur publie le nom. Deux sources pour une enseigne — le jour d'un
/// changement de partenaire, ce bouton en aurait nommé un autre.
void main() {
  /// Les fichiers qui montrent quelque chose du partenariat.
  const ecrans = [
    'lib/features/bankroll/presentation/widgets/miser_dialog.dart',
    'lib/features/pronostics/presentation/pages/match_detail/bookmaker_cotes.dart',
  ];

  /// Un fichier sans ses commentaires : ils citent « 1xBet » pour expliquer le
  /// défaut, et un contrôle qui se valide sur sa propre prose ne contrôle rien.
  String codeSeul(String chemin) => File(chemin)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  group('partenariat non configuré', () {
    test('chaque écran vérifie « disponible » avant d\'afficher', () {
      final fautifs = <String>[];
      for (final e in ecrans) {
        if (!codeSeul(e).contains('BookmakerAffiliation.disponible')) {
          fautifs.add(e.split('/').last);
        }
      }

      expect(fautifs, isEmpty,
        reason: 'écran(s) affichant l\'affiliation sans la vérifier : '
                '${fautifs.join(', ')}');
    });

    test('aucune enseigne n\'est écrite en dur', () {
      // Le nom vient de `/config`. Le trouver en littéral quelque part signifie
      // qu'une seconde source est réapparue.
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)
          .whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final chemin = f.path.replaceAll(RegExp(r'\\'), '/');

        // Deux fichiers nomment légitimement des enseignes, et le garde le
        // dit plutôt que de les ignorer en silence :
        //
        //  - `legal_page` cite l'opérateur dans un texte réglementaire sur le
        //    jeu responsable — une obligation, pas une étiquette de marque ;
        //  - `activer_premium_page` énumère les plateformes du parcours code
        //    promo. Cet ensemble est fixe et structurel : le serveur porte une
        //    clé par plateforme (PROMO_CODE_1XBET, _MELBET, _BETWINNER). C'est
        //    une autre chose que le partenaire d'affiliation, qui est unique et
        //    servi par `/config`.
        if (chemin.endsWith('legal_page.dart')) continue;
        if (chemin.endsWith('activer_premium_page.dart')) continue;

        // Recherche littérale : les commentaires sont déjà retirés, donc toute
        // occurrence restante est du code. C'est plus strict qu'un motif sur
        // les guillemets — et une chaîne brute Dart ne peut de toute façon pas
        // contenir un guillemet échappé.
        if (codeSeul(f.path).contains('1xBet')) {
          fautifs.add(chemin);
        }
      }

      expect(fautifs, isEmpty,
        reason: 'enseigne écrite en dur :\n${fautifs.join('\n')}');
    });

    test('le nom affiché vient bien du serveur', () {
      expect(codeSeul(ecrans[0]), contains('BookmakerAffiliation.nom'));
    });
  });
}
