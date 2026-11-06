import 'package:pronowin/l10n/football_labels.dart';
import 'package:pronowin/l10n/app_strings.dart';
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
String nomEquipe(String nom) => FootballLabels.country(nom);

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
  final language = AppStrings.current.locale.languageCode;
  for (final equipe in equipes) {
    final localized = FootballLabels.country(equipe, language: language);
    for (final from in {FootballLabels.country(equipe, language: 'fr'), FootballLabels.country(equipe, language: 'en')}) {
      if (from == localized || from.isEmpty) continue;
      s = s.replaceAll(RegExp('(?<![\\p{L}])${RegExp.escape(from)}(?![\\p{L}])', unicode: true), localized);
    }
  }
  return s;
}
