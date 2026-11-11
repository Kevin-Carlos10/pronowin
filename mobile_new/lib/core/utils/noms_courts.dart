/// Les noms d'équipe courts, pour les places étroites (10 novembre 2026).
///
/// Sofascore écrit « Man Utd », « PSG », « M'gladbach » dans ses listes, là
/// où PronoWin coupait « Manchester Uni… ». Le nom court ne remplace le nom
/// complet que s'il ne tient pas (`NomEquipeAdapte`) : il reste un repli.
///
/// Deux sources : un dictionnaire des noms longs les plus vus (clubs des
/// grands championnats, sélections aux noms composés), puis, pour les autres,
/// le retrait des sigles de forme juridique (« FC », « AS », « VfB »…) qui ne
/// distinguent pas une équipe d'une autre.
library;

const Map<String, String> _abreviations = {
  // Angleterre
  'manchester united': 'Man Utd',
  'manchester city': 'Man City',
  'nottingham forest': 'Nott. Forest',
  'wolverhampton wanderers': 'Wolves',
  'wolverhampton': 'Wolves',
  'brighton & hove albion': 'Brighton',
  'brighton and hove albion': 'Brighton',
  'tottenham hotspur': 'Tottenham',
  'newcastle united': 'Newcastle',
  'west ham united': 'West Ham',
  'sheffield united': 'Sheffield Utd',
  'west bromwich albion': 'West Brom',
  'queens park rangers': 'QPR',
  // France
  'paris saint germain': 'PSG',
  'olympique lyonnais': 'Lyon',
  'olympique de marseille': 'Marseille',
  'olympique marseille': 'Marseille',
  'stade rennais': 'Rennes',
  'stade brestois 29': 'Brest',
  // Allemagne
  'borussia dortmund': 'Dortmund',
  'borussia monchengladbach': "M'gladbach",
  'borussia moenchengladbach': "M'gladbach",
  'bayer leverkusen': 'Leverkusen',
  'bayer 04 leverkusen': 'Leverkusen',
  'bayern munchen': 'Bayern',
  'bayern munich': 'Bayern',
  'fc bayern munchen': 'Bayern',
  'eintracht frankfurt': 'Frankfurt',
  // Espagne, Italie, Portugal, Autriche
  'atletico madrid': 'Atlético',
  'athletic club': 'Athletic',
  'athletic bilbao': 'Athletic',
  'real sociedad': 'R. Sociedad',
  'internazionale': 'Inter',
  'inter milan': 'Inter',
  'sporting cp': 'Sporting',
  'sporting lisbon': 'Sporting',
  'red bull salzburg': 'Salzburg',
  // Sélections, en français (les noms sont traduits à la lecture)
  'bosnie herzegovine': 'Bosnie',
  'macedoine du nord': 'Macédoine N.',
  'irlande du nord': 'Irlande N.',
  'guinee equatoriale': 'Guinée éq.',
  'sao tome et principe': 'São Tomé',
  'trinite et tobago': 'Trinité',
  'emirats arabes unis': 'EAU',
  'nouvelle zelande': 'N.-Zélande',
  // … et en anglais
  'bosnia & herzegovina': 'Bosnia',
  'bosnia and herzegovina': 'Bosnia',
  'north macedonia': 'N. Macedonia',
  'northern ireland': 'N. Ireland',
  'equatorial guinea': 'Eq. Guinea',
  'sao tome and principe': 'São Tomé',
  'trinidad and tobago': 'Trinidad',
  'united arab emirates': 'UAE',
  'central african republic': 'CAR',
};

/// Sigles placés devant le nom : « AS Roma », « VfB Stuttgart », « 1. FC Köln ».
const _prefixes = {
  'fc', 'ac', 'as', 'ss', 'ssc', 'us', 'rc', 'rcd', 'cd', 'ca', 'ud', 'sd', 'sv',
  'vfb', 'vfl', 'tsg', 'sl', 'ogc', 'aj', 'es', 'krc', 'kv', 'nk', 'fk', 'sk', '1.',
};

/// Sigles placés après : « Arsenal FC », « Valencia CF », « Brann SK ».
const _suffixes = {'fc', 'cf', 'afc', 'cfc', 'sc', 'fk', 'sk', 'bk', 'if', 'f.c.'};

String _cle(String s) {
  const accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const simples = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buf = StringBuffer();
  for (final r in s.toLowerCase().replaceAll('-', ' ').runes) {
    final c = String.fromCharCode(r);
    final i = accents.indexOf(c);
    buf.write(i >= 0 ? simples[i] : c);
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Le nom court de [nom], ou [nom] lui-même s'il n'y a rien à raccourcir.
/// La catégorie qui suit (« U21 », « W ») est gardée : « Bosnie-Herzégovine
/// U21 » → « Bosnie U21 ».
String nomCourt(String nom) {
  final complet = nom.trim();
  if (complet.isEmpty) return nom;
  final categorie = RegExp(r'^(.+?) (U\d{2}|W)$').firstMatch(complet);
  if (categorie != null) {
    final base = nomCourt(categorie[1]!);
    return base == categorie[1] ? complet : '$base ${categorie[2]}';
  }

  final connu = _abreviations[_cle(complet)];
  if (connu != null) return connu;

  final mots = complet.split(RegExp(r'\s+'));
  // Un sigle n'est retiré que s'il reste un nom d'au moins quatre lettres :
  // « AS Douanes » devient « Douanes », « FC Ba » reste « FC Ba ».
  while (mots.length > 1 && _prefixes.contains(mots.first.toLowerCase())
      && mots.sublist(1).join(' ').length >= 4) {
    mots.removeAt(0);
  }
  while (mots.length > 1 && _suffixes.contains(mots.last.toLowerCase())
      && mots.sublist(0, mots.length - 1).join(' ').length >= 4) {
    mots.removeLast();
  }
  for (var i = 1; i < mots.length; i++) {
    if (mots[i] == 'United') mots[i] = 'Utd';
  }
  final court = mots.join(' ');
  return court.isEmpty ? complet : court;
}
