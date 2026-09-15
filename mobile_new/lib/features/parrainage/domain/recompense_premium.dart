/// Conversion des récompenses de parrainage en jours Premium.
///
/// Le taux fait autorité côté serveur : `referral.service.ts` calcule
/// `(montant / PREMIUM_PRICE_FCFA_MONTHLY) * 30`. La réponse de
/// `/referrals/stats` publie la devise et le seuil de retrait, mais pas ce
/// tarif — le client en garde donc une copie.
///
/// Une copie, pas trois. L'écran de retrait écrivait `(earnings / 5000) * 30`
/// dans son coin, l'écran Compte n'en savait rien, et le libellé
/// « 1 000 FCFA = 6 jours » était une troisième écriture du même rapport. Le
/// jour où le tarif bouge, trois endroits annoncent trois nombres de jours
/// pour un même solde — et aucun ne se signale comme faux.
///
/// Si le serveur finit par publier le tarif, c'est ici qu'il remplace la
/// constante, et nulle part ailleurs.
const int prixMensuelPremiumFCFA = 5000;

/// Nombre de jours Premium qu'ouvre un solde de récompenses.
///
/// Arrondi à l'inférieur, comme le serveur : mieux vaut annoncer un jour de
/// moins que d'en promettre un qui ne sera pas crédité.
int joursPremiumPour(int recompenses) =>
    ((recompenses / prixMensuelPremiumFCFA) * 30).floor();

/// Libellé d'un nombre de jours, singulier compris.
///
/// Le cas zéro compte : une commission inférieure à un jour existe, et
/// afficher « 0 jour » sur une tuile qui s'appelle « ce que ça te rapporte »
/// dit exactement le contraire de ce qui se passe.
String libelleJours(int n) => switch (n) {
      <= 0 => 'moins d\'un jour',
      1    => '1 jour',
      _    => '$n jours',
    };
