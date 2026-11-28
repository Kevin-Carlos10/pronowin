/// Le code que l'abonné compose pour payer — « *144*10*45568158*6000# ».
///
/// ── Pourquoi un modèle plutôt qu'un code écrit une fois ───────────────────
///
/// Le code varie d'un opérateur à l'autre, et il n'existe pas de règle
/// commune : seul l'opérateur sait le sien. Il est donc saisi dans
/// l'administration, sous forme de modèle, et publié par l'API avec le numéro.
///
/// Deux marqueurs y sont remplacés ici : `{numero}` et `{montant}`. Le serveur
/// refuse tout autre marqueur, et refuse surtout qu'un numéro y soit écrit à
/// la main — un numéro figé dans le modèle survivrait au changement du numéro
/// de réception, et enverrait l'argent à l'ancien destinataire sans qu'aucune
/// erreur ne se produise.
library;

/// Le numéro d'abonné, sans indicatif.
///
/// **Les huit derniers chiffres.** C'est la règle déjà appliquée à l'affichage
/// du numéro de réception, et elle vaut dans l'espace UEMOA, où les indicatifs
/// font trois chiffres (226, 225, 221…) et les numéros nationaux huit.
///
/// Cette définition vit ici, une fois, et l'affichage la reprend. En garder
/// deux — une pour montrer, une pour composer — laisserait l'écran afficher un
/// numéro et en composer un autre. Personne ne s'en apercevrait avant le
/// virement.
String numeroAbonne(String brut) {
  final chiffres = brut.replaceAll(RegExp(r'\D'), '');
  return chiffres.length > 8
      ? chiffres.substring(chiffres.length - 8)
      : chiffres;
}

/// Le code à composer, ou `null` s'il n'y en a pas à proposer.
///
/// `null` dans trois cas, et c'est voulu :
///
///  - aucun modèle n'est configuré pour cet opérateur — tous n'en ont pas ;
///  - le numéro est inexploitable ;
///  - un marqueur inconnu subsiste après remplacement.
///
/// Ce dernier mérite une note. Un modèle contenant `{somme}` passerait le
/// contrôle du serveur s'il était saisi avant que ce marqueur n'existe, ou par
/// une version plus ancienne de l'API. Afficher « *144*10*45568158*{somme}# »
/// donnerait un code que l'abonné composerait tel quel, qui échouerait chez
/// l'opérateur, et qu'il nous reprocherait. Mieux vaut n'afficher que le
/// numéro, ce que l'écran sait faire.
String? construireCodeUssd({
  required String? modele,
  required String numero,
  required int montant,
}) {
  final m = (modele ?? '').trim();
  if (m.isEmpty) return null;

  final abonne = numeroAbonne(numero);
  if (abonne.isEmpty) return null;

  final code = m
      .replaceAll('{numero}', abonne)
      // Sans séparateur : ce nombre est composé, pas lu. « 54 000 » ferait
      // échouer l'appel.
      .replaceAll('{montant}', montant.toString());

  if (code.contains('{')) return null;
  return code;
}
