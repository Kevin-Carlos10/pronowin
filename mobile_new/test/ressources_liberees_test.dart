import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Toute ressource créée par un `State` doit être libérée.
///
/// Un `AnimationController` oublié continue de faire battre le moteur de rendu
/// après la fermeture de l'écran ; un `Timer.periodic` continue de tirer des
/// requêtes ; un `StreamSubscription` garde en vie tout ce que sa fermeture
/// aurait relâché. Rien de tout cela ne plante : l'application chauffe, la
/// batterie descend, et personne ne relie l'un à l'autre.
///
/// Le balayage initial n'a rien trouvé — cinquante-sept ressources, toutes
/// libérées. Ce contrôle existe pour que cela reste vrai : c'est en ajoutant le
/// cinquante-huitième contrôleur, six mois plus tard, qu'on oublie.
///
/// Trois formes de libération sont reconnues, parce que les trois sont
/// employées ici et qu'un analyseur qui n'en connaîtrait qu'une accuserait à
/// tort. Mon premier prototype ignorait les deux dernières et signalait deux
/// faux positifs sur deux :
///
///   _ctrl.dispose();                       appel direct
///   _ctrl..removeListener(x)..dispose();   cascade, parfois sur trois lignes
///   for (final c in _liste) c.dispose();   boucle sur une collection
void main() {
  /// Types dont l'oubli coûte quelque chose.
  const types = [
    'AnimationController', 'TextEditingController', 'FocusNode',
    'ScrollController', 'PageController', 'TabController',
    'StreamSubscription', 'Timer',
  ];

  final creation = RegExp(
    '(?:late\\s+)?(?:final\\s+)?[\\w<>?]*\\s*(_\\w+)\\s*=\\s*[^;]*?'
    '(${types.join('|')})\\s*[(.]');

  /// Un identifiant suivi — même de loin — d'une libération.
  ///
  /// La cascade `_ctrl\n  ..removeListener(f)\n  ..dispose();` sépare le nom du
  /// `dispose` par plusieurs lignes : on autorise donc tout ce qui n'est pas un
  /// point-virgule entre les deux.
  RegExp libereDirect(String nom) =>
      RegExp('\\b$nom[!?]?\\s*(?:\\.\\.?[\\w]+\\([^;]*\\)\\s*)*'
             '\\.\\.?(?:dispose|cancel|close)\\s*\\(');

  /// `for (final c in _liste) { c.dispose(); }` — la collection est libérée
  /// élément par élément, le nom de la variable de boucle n'a rien à voir.
  RegExp libereEnBoucle(String nom) =>
      RegExp('for\\s*\\([^)]*\\bin\\s+$nom\\b[^)]*\\)[^;]*'
             '\\.(?:dispose|cancel|close)\\s*\\(', dotAll: true);

  final etats = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) {
        final s = f.readAsStringSync();
        return s.contains('extends State<') ||
               s.contains('extends ConsumerState<');
      })
      .toList();

  test('l\'analyseur voit bien le projet', () {
    // Une extraction qui ne trouve rien rendrait le contrôle suivant vert par
    // vacuité — c'est le mode de panne le plus courant de ce genre de test.
    var suivies = 0;
    for (final f in etats) {
      suivies += creation.allMatches(f.readAsStringSync()).length;
    }

    expect(etats.length, greaterThanOrEqualTo(15),
      reason: 'ANALYSEUR DÉFAILLANT : ${etats.length} classes State lues');
    expect(suivies, greaterThanOrEqualTo(40),
      reason: 'ANALYSEUR DÉFAILLANT : $suivies ressources suivies');
  });

  test('aucune ressource n\'est laissée derrière', () {
    final fuites = <String>[];

    for (final f in etats) {
      final src = f.readAsStringSync();
      final chemin = f.path.replaceAll(RegExp(r'\\'), '/');

      for (final m in creation.allMatches(src)) {
        final nom  = m.group(1)!;
        final type = m.group(2)!;

        if (libereDirect(nom).hasMatch(src)) continue;
        if (libereEnBoucle(nom).hasMatch(src)) continue;

        fuites.add('$chemin  →  $nom ($type)');
      }
    }

    expect(fuites, isEmpty,
      reason: 'ressource créée et jamais libérée :\n${fuites.join('\n')}');
  });

  test('chaque State qui crée une ressource déclare un dispose', () {
    // Une classe qui crée sans jamais déclarer `dispose` est le cas le plus
    // net : il n'y a même pas d'endroit où la libération aurait pu être écrite.
    final sansDispose = <String>[];

    for (final f in etats) {
      final src = f.readAsStringSync();
      if (creation.allMatches(src).isEmpty) continue;
      if (src.contains('void dispose()')) continue;

      sansDispose.add(f.path.replaceAll(RegExp(r'\\'), '/'));
    }

    expect(sansDispose, isEmpty);
  });
}
