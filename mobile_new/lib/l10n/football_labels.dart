import 'dart:convert';
import 'app_strings.dart';
import 'football_catalog.dart';

/// Deterministic display labels. Never use translated strings as settlement keys.
class FootballLabel {
  final String text;
  final bool known;
  const FootballLabel(this.text, this.known);
}

class FootballLabels {
  static final Map<String, dynamic> _catalog =
      jsonDecode(footballCatalogJson) as Map<String, dynamic>;
  static String _norm(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static String _lang(String? language) => language == null
      ? AppStrings.current.locale.languageCode
      : AppStrings.normaliseLanguage(language);

  static FootballLabel _lookup(String table, String value, String language) {
    for (final raw in _catalog[table] as List) {
      final x = raw as Map<String, dynamic>;
      if ([
        x['en'],
        x['fr'],
        ...x['aliases'] as List,
      ].any((s) => _norm(s as String) == _norm(value))) {
        return FootballLabel(x[language] as String, true);
      }
    }
    return FootballLabel(value, false);
  }

  static String country(String value, {String? language}) {
    final l = _lang(language), r = _lookup('countries', value, _lang(language));
    if (r.known) return r.text;
    final m = RegExp(r'^(.+?) (U\d{2}|W)$').firstMatch(value);
    return m == null ? value : '${country(m[1]!, language: l)} ${m[2]}';
  }

  static FootballLabel market(String value, {String? language}) =>
      _lookup('markets', value, _lang(language));

  static FootballLabel selection(
    String value, {
    String? language,
    String home = '',
    String away = '',
    int depth = 0,
  }) {
    final s = value.trim(), l = _lang(language);
    if (depth > 4) return FootballLabel(s, false);
    for (final team in [home, away]) {
      if (team.isNotEmpty &&
          [
            team,
            country(team, language: 'fr'),
            country(team, language: 'en'),
          ].any((t) => _norm(t) == _norm(s))) {
        return FootballLabel(country(team, language: l), true);
      }
    }
    final basic = _lookup('selections', s, l);
    if (basic.known) {
      if (['home', 'domicile'].contains(_norm(s)) && home.isNotEmpty)
        return FootballLabel(country(home, language: l), true);
      if (['away', 'extérieur'].contains(_norm(s)) && away.isNotEmpty)
        return FootballLabel(country(away, language: l), true);
      return basic;
    }
    final t = RegExp(
      r'^(Over|Under|Exactly|Plus de|Moins de|Exactement|Home|Away|Domicile|Extérieur)\s+([+-]?\d+(?:[.,]\d+)?)$',
      caseSensitive: false,
    ).firstMatch(s);
    if (t != null) {
      final selected = selection(
        t[1]!,
        language: l,
        home: home,
        away: away,
        depth: depth + 1,
      );
      final number = t[2]!.replaceFirst(
        l == 'fr' ? '.' : ',',
        l == 'fr' ? ',' : '.',
      );
      return FootballLabel('${selected.text} $number', selected.known);
    }
    if (RegExp(r'^[+-]?\d+(?:[.,]\d+)?$').hasMatch(s) ||
        RegExp(r'^\d+\s*[-:]\s*\d+$').hasMatch(s))
      return FootballLabel(s, true);
    if (['1X', 'X2', '12', '1', 'X', '2'].contains(s.toUpperCase()))
      return FootballLabel(s.toUpperCase(), true);
    for (final split in [
      (RegExp(r'\s+(?:or|ou)\s+', caseSensitive: false), ' ou ', ' or '),
      (RegExp(r'\s+(?:and|et)\s+', caseSensitive: false), ' et ', ' and '),
      (RegExp(r'\s*/\s*'), ' / ', ' / '),
    ]) {
      final parts = s.split(split.$1);
      if (parts.length > 1 && parts.length <= 4) {
        final values = parts
            .map(
              (p) => selection(
                p,
                language: l,
                home: home,
                away: away,
                depth: depth + 1,
              ),
            )
            .toList();
        if (values.every((v) => v.known))
          return FootballLabel(
            values.map((v) => v.text).join(l == 'fr' ? split.$2 : split.$3),
            true,
          );
      }
    }
    return FootballLabel(s, false);
  }

  static FootballLabel prediction(
    String value, {
    String? language,
    String home = '',
    String away = '',
  }) {
    final s = value.trim(),
        l = _lang(language),
        colon = value.trim().indexOf(':');
    if (colon > 0) {
      final m = market(s.substring(0, colon), language: l);
      if (m.known) {
        final v = selection(
          s.substring(colon + 1),
          language: l,
          home: home,
          away: away,
        );
        return FootballLabel('${m.text} : ${v.text}', v.known);
      }
    }
    final m = market(s, language: l);
    if (m.known) return m;
    if (RegExp(r'^(?:Match nul|Draw)$', caseSensitive: false).hasMatch(s))
      return FootballLabel(l == 'fr' ? 'Match nul' : 'Draw', true);
    final goals =
        RegExp(
          r'^([+-])(\d+(?:[.,]\d+)?) (?:buts?|goals?)$',
          caseSensitive: false,
        ).firstMatch(s) ??
        RegExp(
          r'^(Plus de|Moins de|Over|Under) (\d+(?:[.,]\d+)?) (?:buts?|goals?)$',
          caseSensitive: false,
        ).firstMatch(s);
    if (goals != null) {
      final over = ['+', 'plus de', 'over'].contains(goals[1]!.toLowerCase());
      final number = goals[2]!.replaceFirst(
        l == 'fr' ? '.' : ',',
        l == 'fr' ? ',' : '.',
      );
      final sense = l == 'fr'
          ? (over ? 'Plus de' : 'Moins de')
          : (over ? 'Over' : 'Under');
      return FootballLabel(
        '$sense $number ${l == 'fr' ? 'buts' : 'goals'}',
        true,
      );
    }
    final win = RegExp(
      r'^(.+?) (?:gagne|wins)$',
      caseSensitive: false,
    ).firstMatch(s);
    if (win != null) {
      final v = selection(win[1]!, language: l, home: home, away: away);
      if (v.known)
        return FootballLabel('${v.text} ${l == 'fr' ? 'gagne' : 'wins'}', true);
    }
    return FootballLabel(s, false);
  }

  static FootballLabel absence(String value, {String? language}) =>
      _lookup('absences', value, _lang(language));
  static FootballLabel transfer(String value, {String? language}) =>
      _lookup('transfers', value, _lang(language));

  static String round(String value, {String? language}) {
    final l = _lang(language),
        found = _lookup('rounds', value, _lang(language));
    if (found.known) return found.text;
    for (final raw in _catalog['roundRules'] as List) {
      final rule = raw as Map<String, dynamic>;
      for (final pattern in rule['patterns'] as List) {
        final m = RegExp(
          pattern as String,
          caseSensitive: false,
        ).firstMatch(value);
        if (m != null)
          return (rule[l] as String).replaceAllMapped(
            RegExp(r'\{(\d+)\}'),
            (placeholder) => m[int.parse(placeholder[1]!)]!,
          );
      }
    }
    return value;
  }
}
