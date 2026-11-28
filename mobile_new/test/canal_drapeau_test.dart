import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/core/config/distribution_channel.dart';

/// Le drapeau de compilation arrive-t-il jusqu'au provider ?
///
/// `canal_store_test.dart` prouve que chaque surface sensible est précédée
/// d'une garde sur `isStoreBuildProvider`. Il ne prouve pas que ce provider
/// répond `true` dans le binaire soumis à Google : entre `--dart-define` et la
/// garde, il y a `String.fromEnvironment`, une comparaison de chaînes et un
/// provider. Si ce chemin cassait — nom de variable changé, valeur mal
/// orthographiée, comparaison inversée — toutes les gardes resteraient en
/// place et ne garderaient plus rien. Aucun test ne le voyait, et l'écran non
/// plus : le canal direct s'affiche normalement, il montre simplement ce qu'il
/// ne devrait pas.
///
/// ── Pourquoi deux groupes plutôt qu'un `skip` ─────────────────────────────
///
/// La première version de ce fichier exigeait le drapeau et faisait échouer
/// `flutter test` sans lui. Le réflexe aurait été de sauter les cas quand le
/// drapeau manque — mais un test sauté ne prouve rien, et c'est précisément le
/// défaut que ce fichier existe pour empêcher.
///
/// Sans drapeau, il reste pourtant quelque chose de vrai à vérifier, et qui
/// vaut cher : que le défaut penche du côté store. `distribution_channel.dart`
/// l'annonce en toutes lettres — un build lancé sans drapeau doit se comporter
/// comme un build publié, parce que l'oubli inverse est un motif de retrait
/// d'application. Chaque exécution contrôle donc l'un ou l'autre, jamais rien.
///
/// Les deux valeurs explicites se lancent avec `tool/verifier_canal.ps1`, ou
/// à la main :
///
///     flutter test test/canal_drapeau_test.dart --dart-define=STORE_BUILD=true
///     flutter test test/canal_drapeau_test.dart --dart-define=STORE_BUILD=false
void main() {
  // Relu ici, indépendamment de `distribution_channel.dart` : si les deux
  // lisaient la même constante, le test suivrait la faute au lieu de la voir.
  const drapeau = String.fromEnvironment('STORE_BUILD');
  const avecDrapeau = drapeau == 'true' || drapeau == 'false';

  late ProviderContainer conteneur;
  setUp(() => conteneur = ProviderContainer());
  tearDown(() => conteneur.dispose());

  group('drapeau explicite (STORE_BUILD=$drapeau)', () {
    test('canalExplicite reconnaît le drapeau', () {
      expect(canalExplicite, isTrue,
        reason: 'le drapeau est passé mais canalExplicite le nie : '
                'la lecture de STORE_BUILD ne fonctionne plus');
    });

    test('le provider est d\'accord avec le drapeau', () {
      final estStore = conteneur.read(isStoreBuildProvider);
      expect(estStore, drapeau == 'true',
        reason: 'STORE_BUILD=$drapeau mais isStoreBuildProvider vaut '
                '$estStore — les gardes de canal_store_test ne protègent '
                'plus rien');
    });

    test('le canal nommé suit la même règle', () {
      expect(conteneur.read(canalDistributionProvider),
        drapeau == 'false'
            ? CanalDistribution.direct
            : CanalDistribution.store);
    });
  }, skip: avecDrapeau
      ? false
      : 'sans drapeau : voir le groupe « défaut de sécurité », et '
        'tool/verifier_canal.ps1 pour les deux valeurs explicites');

  group('défaut de sécurité (aucun drapeau)', () {
    test('canalExplicite signale l\'absence de choix', () {
      expect(canalExplicite, isFalse,
        reason: 'aucun drapeau passé, mais canalExplicite prétend le '
                'contraire : le diagnostic de build est faux');
    });

    test('le canal retombe sur store, pas sur direct', () {
      // Le sens de ce défaut est tout l'enjeu. À l'envers, un build lancé
      // sans drapeau part sur Play avec le renvoi bookmaker et le paiement
      // Mobile Money : pas une mise à jour refusée, un retrait d'application.
      expect(conteneur.read(canalDistributionProvider),
        CanalDistribution.store,
        reason: 'un build sans drapeau doit se comporter comme un build '
                'publié — l\'oubli inverse ne se voit pas et se sanctionne');
      expect(conteneur.read(isStoreBuildProvider), isTrue);
    });
  }, skip: avecDrapeau
      ? 'STORE_BUILD=$drapeau : le défaut ne s\'applique pas'
      : false);
}
