/// Le code d'un fichier, sans ses commentaires.
///
/// ── Pourquoi ce partage existe ────────────────────────────────────────────
///
/// Beaucoup de contrôles de ce projet lisent une source et y cherchent une
/// phrase : un libellé retiré, une valeur qui ne doit plus être écrite en dur,
/// un texte qui doit être affiché.
///
/// Or les commentaires d'ici **citent volontairement** ce qui a été supprimé —
/// c'est ce qui rend les corrections compréhensibles des mois plus tard. Un
/// contrôle qui lit le fichier entier se valide donc sur sa propre explication.
///
/// Le piège s'est refermé quatre fois dans une seule séance de travail :
///
///   · « optimales » cherché dans toute la page, alors que le commentaire
///     expliquait pourquoi ce mot avait été retiré ;
///   · « 30 jours » trouvé dans un sous-titre voisin, laissant la confirmation
///     se taire sans que rien ne tombe ;
///   · « canLaunchUrl » interdit partout, alors que le commentaire doit le
///     nommer pour dire pourquoi il est écarté ;
///   · le domaine mort cité dans l'explication de son propre retrait.
///
/// À chaque fois, le contrôle échouait sur du texte juste, ou passait sur du
/// code faux. Les deux sont également inutiles.
///
/// ── Ce que cela ne remplace pas ───────────────────────────────────────────
///
/// Lire le code reste un pis-aller : il dit ce qui est écrit, pas ce qui se
/// produit. Quand un comportement peut être exercé, l'exercer vaut mieux.
String codeSeul(String source) => source
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

/// Sucre d'écriture : `fichier.readAsStringSync().pipeCodeSeul()`.
///
/// Enveloppe la lecture au plus près de sa source, pour qu'aucune assertion en
/// aval ne puisse voir le fichier non filtré.
extension CodeSeulSurString on String {
  String pipeCodeSeul() => codeSeul(this);
}
