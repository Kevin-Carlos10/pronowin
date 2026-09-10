import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Toute navigation littérale doit viser une route qui existe.
///
/// Un `context.go('/abonnement')` compile, passe l'analyse statique et ne
/// déclenche aucun avertissement. Il échoue à l'exécution, sur la page d'erreur
/// du routeur, et seulement si quelqu'un touche ce bouton précis. Deux l'ont
/// fait sans être vus :
///
///  - « Plan Gratuit · Passer Premium ✨ » en haut de l'accueil — le premier
///    appel à l'abonnement que voit un compte gratuit ;
///  - « Se déconnecter » depuis l'écran de verrouillage — au moment où
///    l'utilisateur n'a plus d'autre chemin, puisqu'il a oublié son code.
///
/// Angle mort assumé : seules les destinations écrites en clair sont vérifiées.
/// Un chemin construit dans une variable échappe à ce test.
void main() {
  final routeur = File('lib/core/router/app_router.dart').readAsStringSync();

  final routes = RegExp(r"path:\s*'([^']+)'")
      .allMatches(routeur)
      .map((m) => m.group(1)!)
      .where((p) => p.startsWith('/'))
      .toList();

  final navigations = _collecterNavigations();

  group('navigation — aucune destination morte', () {
    test('l\'analyseur a effectivement lu quelque chose', () {
      // Une extraction qui rend trop peu ne prouve rien : elle rend le test
      // vert parce qu'elle n'a rien trouvé à comparer. Mieux vaut qu'il tombe
      // bruyamment le jour où la forme du code change.
      expect(routes.length, greaterThanOrEqualTo(20),
        reason: 'ANALYSEUR DÉFAILLANT : ${routes.length} routes extraites');
      expect(navigations.length, greaterThanOrEqualTo(30),
        reason: 'ANALYSEUR DÉFAILLANT : ${navigations.length} navigations extraites');
    });

    test('aucune destination n\'échappe à l\'analyse', () {
      // Une interpolation au milieu d'un segment (`/foo/bar${x}`) ne se compare
      // pas segment par segment. Aucune n'existe aujourd'hui ; si une apparaît,
      // ce test la signale au lieu de la comparer de travers.
      final opaques = navigations.where((n) => n.opaque).toList();

      expect(opaques, isEmpty,
        reason: opaques.map((n) => '${n.fichier}:${n.ligne} → ${n.brut}').join('\n'));
    });

    test('chaque destination correspond à une route déclarée', () {
      final mortes = navigations
          .where((n) => !routes.any((r) => n.correspondA(r)))
          .map((n) => '${n.fichier}:${n.ligne} → ${n.brut}')
          .toList();

      expect(mortes, isEmpty,
        reason: 'destinations sans route :\n${mortes.join('\n')}');
    });
  });

  group('mentions légales du paywall', () {
    // Le cas limite du même défaut : pas une mauvaise destination, aucune
    // destination. « CGU · Confidentialité · Contact » étaient trois `Text`
    // nus, sans zone tactile. Toucher « Confidentialité » ne faisait rien.
    //
    // C'est aussi l'écran où Apple exige des liens *fonctionnels* vers les
    // conditions d'utilisation et la politique de confidentialité (3.1.2).
    final paywall = File(
      'lib/features/abonnement/presentation/pages/activer_premium_page.dart',
    ).readAsStringSync();

    /// Le pied de page du paywall, borné à la ligne des mentions.
    ///
    /// L'ancre tolère les espaces : les fichiers sont en CRLF, et un `\n`
    /// écrit à la main dans une chaîne de test ne correspond à rien.
    String piedDePage() {
      final debut = paywall.indexOf(RegExp(r"_LienLegal\(\s*libelle: 'CGU'"));
      expect(debut, greaterThan(-1),
        reason: 'ancre du pied de page introuvable — test à réécrire');
      final fin = paywall.indexOf(']),', debut);
      return paywall.substring(debut, fin == -1 ? paywall.length : fin);
    }

    test('les trois mentions sont cliquables', () {
      final pied = piedDePage();

      for (final libelle in ['CGU', 'Confidentialité', 'Contact']) {
        expect(pied, contains("libelle: '$libelle'"));
      }
      // Trois mentions, trois liens : aucune ne reste un simple libellé.
      expect(RegExp('_LienLegal\\(').allMatches(pied).length, 3);
    });

    test('chaque mention mène quelque part', () {
      final pied = piedDePage();

      expect(pied, contains("context.push('/parametres/cgu')"));
      expect(pied, contains("context.push('/parametres/confidentialite')"));
      expect(pied, contains('ContactSupport.ouvrirEmail'));
    });

    test('la cible tactile dépasse la taille du texte', () {
      // Un lien correctement câblé mais large de onze pixels se comporte,
      // pour le pouce qui le vise, exactement comme un lien mort.
      final debut = paywall.indexOf('class _LienLegal');
      expect(debut, greaterThan(-1));
      final corps = paywall.substring(debut, paywall.indexOf('\nclass ', debut + 1));

      final m = RegExp(r'vertical:\s*(\d+)').firstMatch(corps);
      expect(m, isNotNull, reason: 'aucun rembourrage vertical déclaré');
      expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(10));

      // Et le lecteur d'écran doit l'annoncer comme un lien.
      expect(corps, contains('link: true'));
    });
  });
}

/// Une navigation trouvée dans le code, réduite à son préfixe littéral.
class _Nav {
  /// Segments certains, avant toute interpolation ou paramètre de requête.
  final List<String> segments;

  /// `true` si un segment dynamique suit — `/pronostics/${p.id}`.
  final bool segmentDynamique;

  /// `true` si le chemin ne se découpe pas proprement : on refuse de conclure.
  final bool opaque;

  final String fichier, brut;
  final int ligne;

  _Nav(this.segments, this.segmentDynamique, this.opaque,
       this.fichier, this.ligne, this.brut);

  bool correspondA(String route) {
    final r = route.split('/').where((s) => s.isNotEmpty).toList();

    if (segmentDynamique) {
      // Exactement un segment de plus, et il doit être un paramètre.
      if (r.length != segments.length + 1) return false;
      if (!r[segments.length].startsWith(':')) return false;
    } else if (r.length != segments.length) {
      return false;
    }

    for (var i = 0; i < segments.length; i++) {
      if (r[i] != segments[i] && !r[i].startsWith(':')) return false;
    }
    return true;
  }
}

List<_Nav> _collecterNavigations() {
  final debut = RegExp(r"context\.(?:push|go|replace)\(\s*'");
  final out   = <_Nav>[];

  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {

    final lignes = f.readAsLinesSync();

    for (var i = 0; i < lignes.length; i++) {
      // Une ligne commentée n'est pas du code.
      if (lignes[i].trimLeft().startsWith('//')) continue;

      for (final m in debut.allMatches(lignes[i])) {
        final reste = lignes[i].substring(m.end);

        // Le préfixe s'arrête à la première interpolation, au premier
        // paramètre de requête, ou à la fin de la chaîne.
        var fin = reste.length;
        var coupePar = "'";
        for (var j = 0; j < reste.length; j++) {
          final c = reste[j];
          if (c == "'" || c == r'$' || c == '?') { fin = j; coupePar = c; break; }
        }
        final brut = reste.substring(0, fin);
        if (!brut.startsWith('/')) continue;

        // Interpolation collée à un segment : indécidable segment par segment.
        final opaque = coupePar == r'$' && !brut.endsWith('/');

        out.add(_Nav(
          brut.split('/').where((s) => s.isNotEmpty).toList(),
          coupePar == r'$' && brut.endsWith('/'),
          opaque,
          f.path.replaceAll(r'\', '/'),
          i + 1,
          brut,
        ));
      }
    }
  }
  return out;
}
