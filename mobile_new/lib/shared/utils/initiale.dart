/// La lettre de l'avatar, la même sur tous les écrans.
///
/// Trois écrans la calculaient chacun à sa façon : l'Accueil et « Modifier le
/// profil » prenaient la première lettre du pseudo, la page Compte celle du
/// nom affiché. Vu sur iPhone : « P » (Parieur_7AGY8) sur l'Accueil, « B »
/// (boss gand) sur le Compte, pour la même personne.
///
/// La règle est celle du nom par lequel l'application salue l'utilisateur
/// (« Bonjour, boss ») : le prénom s'il est renseigné, sinon le pseudo.
String initialeAvatar({String? prenom, String? pseudo}) {
  for (final source in [prenom, pseudo]) {
    final s = source?.trim() ?? '';
    if (s.isNotEmpty) return String.fromCharCode(s.runes.first).toUpperCase();
  }
  return 'P';
}
