import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'onglet sur lequel l'application s'ouvre (8 novembre 2026), comme
/// l'« Onglet principal » des préférences de Sofascore : l'accueil, la liste
/// des pronostics, ou les matchs suivis.
enum OngletDemarrage { accueil, pronos, suivis }

const cleOngletDemarrage = 'onglet_demarrage';

OngletDemarrage ongletDepuisPreference(String? v) =>
    OngletDemarrage.values.where((o) => o.name == v).firstOrNull ?? OngletDemarrage.accueil;

/// Le chemin d'ouverture de [o].
String cheminDemarrage(OngletDemarrage o) => o == OngletDemarrage.accueil ? '/home' : '/pronostics';

/// Lu au démarrage (main.dart) ; changé dans Paramètres, il vaut pour la
/// prochaine ouverture.
final ongletDemarrageProvider = StateProvider<OngletDemarrage>((ref) => OngletDemarrage.accueil);

/// Vrai jusqu'à la première ouverture de la liste des pronostics, quand
/// l'application doit s'ouvrir sur « Suivis ».
final ouvrirSurSuivisProvider = StateProvider<bool>((ref) => false);

Future<void> enregistrerOngletDemarrage(WidgetRef ref, OngletDemarrage o) async {
  ref.read(ongletDemarrageProvider.notifier).state = o;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cleOngletDemarrage, o.name);
  } catch (_) {}
}
