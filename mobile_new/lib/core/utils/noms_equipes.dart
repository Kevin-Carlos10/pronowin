/// Les sélections nationales, en français.
///
/// Le fournisseur de données écrit les pays en anglais : « Belgium »,
/// « Norway », « Türkiye ». À côté des libellés de pronostic rédigés en
/// français, l'application affichait « France gagne » au-dessus de
/// « Belgium », et « Belgique gagne » dans l'historique, sous « Belgium ».
///
/// Les noms sont traduits **à la lecture des données**, à chaque endroit où
/// l'application reçoit un nom d'équipe : ainsi tous les écrans affichent le
/// même nom, et deux noms comparés entre eux — l'équipe d'une statistique et
/// celle du match — le sont toujours dans la même langue.
///
/// Seules les sélections nationales sont concernées : un nom de club ne se
/// traduit pas. La catégorie qui suit le nom (« U21 », « W ») est conservée :
/// « Spain U21 » → « Espagne U21 ».
String nomEquipe(String nom) {
  final brut = nom.trim();
  final direct = _pays[brut];
  if (direct != null) return direct;
  final m = _categorie.firstMatch(brut);
  if (m != null) {
    final base = _pays[m.group(1)!.trim()];
    if (base != null) return '$base ${m.group(2)}';
  }
  return nom;
}

/// Variante tolérante pour les champs facultatifs.
String? nomEquipeOuNul(String? nom) => nom == null ? null : nomEquipe(nom);

/// Traduit, dans un libellé de pronostic, le nom anglais des [equipes] du
/// match — et d'elles seules.
///
/// Le formulaire du panneau compose les libellés avec le nom reçu du
/// fournisseur : « Norway gagne ». Traduire tous les pays connus dans tout le
/// libellé toucherait aussi les noms de joueurs (« Jordan Henderson ») ; on se
/// limite donc aux deux sélections qui jouent. Les noms passés peuvent être
/// anglais ou déjà traduits.
String traduireEquipesDansLibelle(String libelle, Iterable<String> equipes) {
  var s = libelle;
  for (final equipe in equipes) {
    final fr = nomEquipe(equipe);
    for (final entree in _pays.entries) {
      if (entree.value != fr) continue;
      s = s.replaceAll(RegExp('(?<![\\p{L}])${RegExp.escape(entree.key)}(?![\\p{L}])', unicode: true), fr);
    }
  }
  return s;
}

final _categorie = RegExp(r'^(.+?)\s+(U\d{2}|W)$');

const _pays = <String, String>{
  // Europe
  'Albania': 'Albanie', 'Andorra': 'Andorre', 'Armenia': 'Arménie', 'Austria': 'Autriche',
  'Azerbaijan': 'Azerbaïdjan', 'Belarus': 'Biélorussie', 'Belgium': 'Belgique',
  'Bosnia & Herzegovina': 'Bosnie-Herzégovine', 'Bosnia and Herzegovina': 'Bosnie-Herzégovine',
  'Bulgaria': 'Bulgarie', 'Croatia': 'Croatie', 'Cyprus': 'Chypre', 'Czech Republic': 'Tchéquie',
  'Czechia': 'Tchéquie', 'Denmark': 'Danemark', 'England': 'Angleterre', 'Estonia': 'Estonie',
  'Faroe Islands': 'Îles Féroé', 'Finland': 'Finlande', 'Georgia': 'Géorgie', 'Germany': 'Allemagne',
  'Greece': 'Grèce', 'Hungary': 'Hongrie', 'Iceland': 'Islande', 'Israel': 'Israël', 'Italy': 'Italie',
  'Kazakhstan': 'Kazakhstan', 'Kosovo': 'Kosovo', 'Latvia': 'Lettonie', 'Lithuania': 'Lituanie',
  'Moldova': 'Moldavie', 'Montenegro': 'Monténégro', 'Netherlands': 'Pays-Bas',
  'North Macedonia': 'Macédoine du Nord', 'FYR Macedonia': 'Macédoine du Nord',
  'Northern Ireland': 'Irlande du Nord', 'Norway': 'Norvège', 'Poland': 'Pologne',
  'Rep. Of Ireland': 'Irlande', 'Republic of Ireland': 'Irlande', 'Ireland': 'Irlande',
  'Romania': 'Roumanie', 'Russia': 'Russie', 'Scotland': 'Écosse', 'Serbia': 'Serbie',
  'Slovakia': 'Slovaquie', 'Slovenia': 'Slovénie', 'Spain': 'Espagne', 'Sweden': 'Suède',
  'Switzerland': 'Suisse', 'Turkey': 'Turquie', 'Türkiye': 'Turquie', 'Ukraine': 'Ukraine',
  'Wales': 'Pays de Galles',
  // Afrique
  'Algeria': 'Algérie', 'Benin': 'Bénin', 'Botswana': 'Botswana', 'Burundi': 'Burundi',
  'Cameroon': 'Cameroun', 'Cape Verde Islands': 'Cap-Vert', 'Cape Verde': 'Cap-Vert',
  'Central African Republic': 'Centrafrique', 'Chad': 'Tchad', 'Comoros': 'Comores',
  'Congo': 'Congo', 'Congo DR': 'RD Congo', 'DR Congo': 'RD Congo', 'Djibouti': 'Djibouti',
  'Egypt': 'Égypte', 'Equatorial Guinea': 'Guinée équatoriale', 'Eritrea': 'Érythrée',
  'Eswatini': 'Eswatini', 'Ethiopia': 'Éthiopie', 'Gambia': 'Gambie', 'Guinea': 'Guinée',
  'Guinea-Bissau': 'Guinée-Bissau', 'Ivory Coast': "Côte d'Ivoire", "Cote D'Ivoire": "Côte d'Ivoire",
  'Kenya': 'Kenya', 'Lesotho': 'Lesotho', 'Liberia': 'Liberia', 'Libya': 'Libye',
  'Madagascar': 'Madagascar', 'Malawi': 'Malawi', 'Mauritania': 'Mauritanie', 'Mauritius': 'Maurice',
  'Morocco': 'Maroc', 'Mozambique': 'Mozambique', 'Namibia': 'Namibie', 'Nigeria': 'Nigeria',
  'Rwanda': 'Rwanda', 'Sao Tome and Principe': 'Sao Tomé-et-Principe', 'Senegal': 'Sénégal',
  'Seychelles': 'Seychelles', 'Sierra Leone': 'Sierra Leone', 'Somalia': 'Somalie',
  'South Africa': 'Afrique du Sud', 'South Sudan': 'Soudan du Sud', 'Sudan': 'Soudan',
  'Tanzania': 'Tanzanie', 'Tunisia': 'Tunisie', 'Uganda': 'Ouganda', 'Zambia': 'Zambie',
  'Zimbabwe': 'Zimbabwe',
  // Amériques
  'Argentina': 'Argentine', 'Bolivia': 'Bolivie', 'Brazil': 'Brésil', 'Canada': 'Canada',
  'Chile': 'Chili', 'Colombia': 'Colombie', 'Costa Rica': 'Costa Rica', 'Curacao': 'Curaçao',
  'Ecuador': 'Équateur', 'El Salvador': 'Salvador', 'Guatemala': 'Guatemala', 'Haiti': 'Haïti',
  'Honduras': 'Honduras', 'Jamaica': 'Jamaïque', 'Mexico': 'Mexique', 'Panama': 'Panama',
  'Paraguay': 'Paraguay', 'Peru': 'Pérou', 'Trinidad and Tobago': 'Trinité-et-Tobago',
  'Uruguay': 'Uruguay', 'USA': 'États-Unis', 'United States': 'États-Unis', 'Venezuela': 'Venezuela',
  // Asie et Océanie
  'Australia': 'Australie', 'Bahrain': 'Bahreïn', 'China': 'Chine', 'China PR': 'Chine',
  'India': 'Inde', 'Indonesia': 'Indonésie', 'Iran': 'Iran', 'Iraq': 'Irak', 'Japan': 'Japon',
  'Jordan': 'Jordanie', 'Korea Republic': 'Corée du Sud', 'South Korea': 'Corée du Sud',
  'North Korea': 'Corée du Nord', 'Kuwait': 'Koweït', 'Lebanon': 'Liban', 'Malaysia': 'Malaisie',
  'New Zealand': 'Nouvelle-Zélande', 'Oman': 'Oman', 'Palestine': 'Palestine', 'Qatar': 'Qatar',
  'Saudi Arabia': 'Arabie saoudite', 'Syria': 'Syrie', 'Thailand': 'Thaïlande',
  'United Arab Emirates': 'Émirats arabes unis', 'Uzbekistan': 'Ouzbékistan', 'Vietnam': 'Viêt Nam',
  'Yemen': 'Yémen',
};
