/// Âge révolu, par arithmétique calendaire.
///
/// L'écran du compte calculait l'âge en divisant un nombre de jours par
/// 365,25 :
///
///     ((DateTime.now().difference(d).inDays) / 365.25).floor()
///
/// L'approximation se trompe d'un an **le jour de l'anniversaire**, selon les
/// années bissextiles traversées : sur trente dates éprouvées, vingt donnaient
/// un an de moins le jour même. Quelqu'un qui a vingt et un ans lisait
/// « 20 ans », le seul jour de l'année où il regarde cette ligne.
///
/// ── Ce calcul existait déjà, corrigé, ailleurs ─────────────────────────────
///
/// `backend/src/utils/age.ts` a remplacé cette même formule par ce même calcul,
/// avec son banc, parce qu'elle décidait de la majorité : se tromper d'un jour
/// sur un seuil légal, c'est se tromper exactement le jour où quelqu'un devient
/// majeur. La règle était donc écrite, corrigée et éprouvée — d'un seul côté.
///
/// Le serveur reste la seule autorité sur la majorité ; l'application ne fait
/// qu'afficher. Mais afficher faux reste afficher faux.
int ageRevolu(DateTime naissance, [DateTime? maintenant]) {
  final m = maintenant ?? DateTime.now();

  var age = m.year - naissance.year;

  final moisEcoule = m.month - naissance.month;
  final jourEcoule = m.day - naissance.day;

  // L'anniversaire de cette année n'est pas encore passé.
  if (moisEcoule < 0 || (moisEcoule == 0 && jourEcoule < 0)) age -= 1;

  return age;
}
