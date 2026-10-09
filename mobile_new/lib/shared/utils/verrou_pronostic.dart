/// Faut-il masquer le contenu payant de ce pronostic ?
///
/// Miroir exact de `estVerrouille` côté serveur (`verrou_pronostic.ts`). Le
/// serveur décide ce qu'il envoie ; cette fonction décide ce que l'écran
/// montre. Les deux doivent dire la même chose, sinon l'application affiche un
/// cadenas sur une donnée qu'elle a reçue — ou l'inverse.
///
/// ── Pourquoi elle existe ──────────────────────────────────────────────────
///
/// La règle « un pronostic payant cesse de l'être une fois le match joué »
/// était appliquée côté serveur et contredite dans cinq écrans, qui
/// calculaient chacun `isPremium && !utilisateurPremium` sans regarder le
/// statut du match. Sur une fiche de match terminé, l'application affichait
/// donc le score, les cotes et le pronostic — puis « Débriefing du modèle »
/// sous un cadenas. Elle ouvrait tout sauf la seule chose qui expliquait le
/// reste.
///
/// Le cas le plus retors était `match_detail_page.dart` :
///
///     final isLocked = match.isLocked || (match.isPremium && !isPremium);
///
/// Le premier terme vient du serveur, qui applique la règle. Le second la
/// contredit. Un `||` entre les deux donne toujours raison à celui qui
/// verrouille : la correction serveur ne pouvait pas atteindre l'écran.
///
/// Il n'y a plus rien à protéger après le coup de sifflet — le pronostic est
/// devenu un résultat, et le cacher ne vend plus rien, cela empêche seulement
/// de juger sa fiabilité avant de s'abonner.
bool estVerrouille({
  required bool estPremium,
  required bool matchTermine,
  required bool utilisateurPremium,
}) {
  if (!estPremium)         return false;
  if (utilisateurPremium)  return false;
  if (matchTermine)        return false;
  return true;
}
