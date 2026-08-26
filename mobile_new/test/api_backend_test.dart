import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Chaque appel du mobile doit atteindre une route que le backend déclare.
///
/// Un chemin absent ne casse rien au démarrage, ne produit aucun avertissement
/// et ne se manifeste qu'à l'usage — par un écran qui reste vide ou un bouton
/// qui « ne marche pas ». Trois cas ont déjà été trouvés à la main dans ce
/// projet, et leurs traces sont encore dans `app_constants.dart` :
/// `/auth/delete-account` qui n'a jamais existé, `/leagues` servi en réalité
/// sous `/pronostics`, et trois constantes d'abonnement pointant dans le vide.
///
/// Deux angles morts, mesurés plutôt que supposés.
///
/// 1. Un chemin entièrement porté par une variable (`dio.get(url)`) échappe à
///    l'analyse. Le test les compte et exige qu'ils restent rares — s'ils se
///    multiplient, la garde ne garde plus grand-chose.
///
/// 2. Une faute dans le **dernier** segment d'un chemin couvert par une route
///    paramétrée passe inaperçue : `/pronostics/perf` correspond à
///    `/pronostics/:id`. Ce n'est pas un défaut de l'analyseur — Express y
///    routerait vraiment l'appel, et répondrait « pronostic introuvable »
///    plutôt qu'un 404. Une faute sur un segment *fixe*, elle, est vue.
void main() {
  final backend = Directory('../backend/src');
  final routes  = _routesBackend(backend);
  final appels  = _appelsMobile();

  group('appels API — aucune route manquante', () {
    test('le backend a bien été lu', () {
      final fichiers = Directory('${backend.path}/routes')
          .listSync().where((f) => f.path.endsWith('.ts')).length;

      // Une extraction qui rend trop peu rend le test vert faute d'avoir
      // trouvé quoi que ce soit à comparer. Trois versions de l'analyseur
      // équivalent côté admin ont produit 39, puis 13, puis 26 faux positifs
      // avant d'être justes : mieux vaut qu'il refuse de conclure.
      expect(backend.existsSync(), isTrue,
        reason: 'backend introuvable depuis ${Directory.current.path}');
      expect(routes.length, greaterThanOrEqualTo(fichiers * 2),
        reason: 'ANALYSEUR DÉFAILLANT : ${routes.length} routes pour '
                '$fichiers fichiers de routes');
    });

    test('les appels du mobile ont bien été lus', () {
      expect(appels.resolus.length, greaterThanOrEqualTo(45),
        reason: 'ANALYSEUR DÉFAILLANT : ${appels.resolus.length} appels lus');
    });

    test('les chemins portés par une variable restent l\'exception', () {
      expect(appels.opaques.length, lessThanOrEqualTo(3),
        reason: 'trop de chemins non analysables :\n'
                '${appels.opaques.join('\n')}');
    });

    test('aucune constante d\'endpoint ne dort', () {
      // Une constante que personne n'utilise donne l'illusion de gouverner un
      // appel. On la modifie, rien ne bouge, et elle diverge en silence du
      // chemin réellement employé. `referral` et `notifications` étaient dans
      // ce cas ; trois autres l'avaient déjà été avant elles.
      final src = File('lib/core/constants/app_constants.dart').readAsStringSync();
      final debut = src.indexOf('class ApiEndpoints');
      expect(debut, greaterThan(-1));

      final declarees = RegExp(r'static\s+const\s+String\s+(\w+)\s*=')
          .allMatches(src.substring(debut))
          .map((m) => m.group(1)!)
          .toList();
      expect(declarees.length, greaterThanOrEqualTo(10),
        reason: 'ANALYSEUR DÉFAILLANT : ${declarees.length} constantes lues');

      final tout = Directory('lib').listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      final dormantes = declarees
          .where((c) => !RegExp('ApiEndpoints\\.$c\\b').hasMatch(tout))
          .toList();

      expect(dormantes, isEmpty);
    });

    test('chaque appel atteint une route déclarée', () {
      final orphelins = <String>[];

      for (final a in appels.resolus) {
        final cible = _segments('/api/v1${a.chemin}');
        final trouve = routes.any((r) =>
            r.methode == a.methode && _correspond(r.segments, cible));
        if (!trouve) orphelins.add('${a.methode} ${a.chemin}   → ${a.origine}');
      }

      expect(orphelins, isEmpty,
        reason: 'appels sans route correspondante :\n${orphelins.join('\n')}');
    });
  });
}

// ── Modèle ────────────────────────────────────────────────────────────────────

class _Route {
  final String methode;
  final List<String?> segments;
  _Route(this.methode, this.segments);
}

class _Appel {
  final String methode, chemin, origine;
  _Appel(this.methode, this.chemin, this.origine);
}

class _Appels {
  final List<_Appel> resolus;
  final List<String> opaques;
  _Appels(this.resolus, this.opaques);
}

/// Découpe un chemin en segments ; `null` marque un joker.
///
/// Il en faut **des deux côtés** : `:id` chez Express et `$matchId` côté
/// mobile désignent la même chose. Compiler une expression depuis la seule
/// route ne pouvait pas faire correspondre les deux.
List<String?> _segments(String chemin) => chemin
    .split('?')
    .first
    .split('/')
    .where((s) => s.isNotEmpty)
    .map<String?>((s) => (s.startsWith(':') || s == '*') ? null : s)
    .toList();

bool _correspond(List<String?> a, List<String?> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => i)
        .every((i) => a[i] == null || b[i] == null || a[i] == b[i]);

// ── Côté backend ──────────────────────────────────────────────────────────────

List<_Route> _routesBackend(Directory racine) {
  if (!racine.existsSync()) return [];

  final index = File('${racine.path}/index.ts').readAsStringSync();

  // Les préfixes sont des gabarits : app.use(`${v1}/auth`, authRoutes).
  final constantes = <String, String>{};
  for (final m in RegExp(r"""const\s+(\w+)\s*=\s*['"]([^'"]+)['"]""")
      .allMatches(index)) {
    constantes[m.group(1)!] = m.group(2)!;
  }
  String resoudre(String s) => s.replaceAllMapped(
      RegExp(r'\$\{(\w+)\}'),
      (m) => constantes[m.group(1)!] ?? m.group(0)!);

  final prefixe  = <String, String>{};
  final fichierDe = <String, String>{};
  for (final m in RegExp(
      r'''app\.use\(\s*[`'"]([^`'"]+)[`'"]\s*,\s*(?:\w+\s*,\s*)*(\w+)\s*\)''')
      .allMatches(index)) {
    prefixe[m.group(2)!] = resoudre(m.group(1)!);
  }
  for (final m in RegExp(
      r'''import\s+(\w+)\s+from\s+['"]\./routes/([\w.]+)['"]''')
      .allMatches(index)) {
    fichierDe[m.group(1)!] = m.group(2)!;
  }

  final out = <_Route>[];
  for (final f in Directory('${racine.path}/routes').listSync()
      .whereType<File>().where((f) => f.path.endsWith('.ts'))) {

    final base  = f.uri.pathSegments.last.replaceAll('.ts', '');
    final ident = fichierDe.keys.firstWhere(
        (k) => fichierDe[k] == base, orElse: () => '');
    final p = prefixe[ident];
    if (p == null) continue;

    final src = f.readAsStringSync();
    // Le nom du routeur varie d'un fichier à l'autre : `router` ici, `r` là.
    final nom = RegExp(r'const\s+(\w+)\s*=\s*(?:express\.)?Router\s*\(')
        .firstMatch(src)?.group(1);
    if (nom == null) continue;

    for (final m in RegExp(
        '\\b$nom\\s*\\.\\s*(get|post|put|patch|delete)\\s*\\(\\s*[`\'"]([^`\'"]*)[`\'"]')
        .allMatches(src)) {
      out.add(_Route(m.group(1)!.toUpperCase(), _segments(p + m.group(2)!)));
    }
  }
  return out;
}

// ── Côté mobile ───────────────────────────────────────────────────────────────

_Appels _appelsMobile() {
  final constantes = <String, String>{};
  for (final m in RegExp(r"""static\s+const\s+String\s+(\w+)\s*=\s*'([^']+)'""")
      .allMatches(File('lib/core/constants/app_constants.dart').readAsStringSync())) {
    constantes[m.group(1)!] = m.group(2)!;
  }

  final resolus = <_Appel>[];
  final opaques = <String>[];

  // Le récepteur n'est pas contraint : `dio.get`, `_dio.post`, et surtout
  // `ref.read(dioProvider).get` — cette dernière forme portait douze appels
  // qu'une expression ancrée sur `dio.` laissait passer. L'appel peut aussi
  // être coupé en deux lignes, d'où la lecture du fichier entier.
  final debut = RegExp(r'\.(get|post|put|patch|delete)(?:<[^>]*>)?\(\s*');

  for (final f in Directory('lib').listSync(recursive: true)
      .whereType<File>().where((f) => f.path.endsWith('.dart'))) {

    final src = f.readAsStringSync();
    for (final m in debut.allMatches(src)) {
      final i = m.end;
      if (i >= src.length) continue;
      if (_dansUnCommentaire(src, m.start)) continue;

      final methode = m.group(1)!.toUpperCase();
      final ou = '${f.path.replaceAll(r'\', '/')}:${_ligne(src, m.start)}';

      // Constante nue : `dio.get(ApiEndpoints.profile)`.
      final cst = RegExp(r'^ApiEndpoints\.(\w+)').firstMatch(src.substring(i));
      if (cst != null) {
        final v = constantes[cst.group(1)!];
        if (v == null) { opaques.add('$ou (constante inconnue)'); continue; }
        resolus.add(_Appel(methode, v, ou));
        continue;
      }

      // Littéral, éventuellement interpolé.
      if (src[i] != "'" && src[i] != '"') continue;   // pas un chemin : ignoré
      final brut = _litteral(src, i);
      if (brut == null) continue;
      if (!brut.startsWith('/') && !brut.startsWith(r'${ApiEndpoints.')) continue;

      final chemin = _normaliser(brut, constantes);
      if (chemin == null) { opaques.add('$ou → $brut'); continue; }
      resolus.add(_Appel(methode, chemin, ou));
    }
  }
  return _Appels(resolus, opaques);
}

/// Contenu brut d'un littéral Dart dont le guillemet ouvrant est à [i].
///
/// Les accolades d'interpolation sont suivies : un guillemet à l'intérieur de
/// `${...}` appartient à l'expression, pas au littéral.
String? _litteral(String src, int i) {
  final quote = src[i];
  final buf   = StringBuffer();
  var profondeur = 0;

  for (var j = i + 1; j < src.length; j++) {
    final c = src[j];
    if (c == '\n') return null;                 // littéral non terminé : on refuse
    if (c == r'\') {
      buf.write(c);
      if (j + 1 < src.length) buf.write(src[++j]);
      continue;
    }
    if (profondeur == 0 && c == quote) return buf.toString();
    if (c == r'$' && j + 1 < src.length && src[j + 1] == '{') profondeur++;
    if (profondeur > 0 && c == '}') profondeur--;
    buf.write(c);
  }
  return null;
}

/// Remplace les interpolations par des jokers ; `null` si une part reste opaque.
String? _normaliser(String brut, Map<String, String> constantes) {
  var s = brut;

  // `'${ApiEndpoints.tutorials}/$id'` → `/tutorials/$id`
  var inconnue = false;
  s = s.replaceAllMapped(RegExp(r'\$\{ApiEndpoints\.(\w+)\}'), (m) {
    final v = constantes[m.group(1)!];
    if (v == null) inconnue = true;
    return v ?? '';
  });
  if (inconnue) return null;

  s = s.replaceAll(RegExp(r'\$\{[^}]*\}'), '*');
  s = s.replaceAll(RegExp(r'\$\w+'), '*');

  // Une interpolation collée au milieu d'un segment ne se compare pas.
  if (s.contains(r'$')) return null;
  return s.replaceAll(RegExp('/{2,}'), '/');
}

int _ligne(String src, int i) => '\n'.allMatches(src.substring(0, i)).length + 1;

/// `true` si la position est précédée d'un `//` sur la même ligne.
bool _dansUnCommentaire(String src, int i) {
  final debutLigne = src.lastIndexOf('\n', i) + 1;
  final avant = src.substring(debutLigne, i);
  // `://` appartient à une URL, pas à un commentaire.
  return RegExp(r'(^|[^:])//').hasMatch(avant);
}
