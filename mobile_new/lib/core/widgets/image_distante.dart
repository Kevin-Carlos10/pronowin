import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Une image venue du réseau, décodée à la taille où elle sera affichée.
///
/// L'application chargeait ses images distantes par dix-sept `Image.network`
/// écrits à la main. Aucun ne passait `cacheWidth` : Flutter décodait donc
/// chaque fichier à sa résolution d'origine — un écusson de 512 px pour une
/// case de 16, une photo de joueur de 500 px pour un rond de 26. Un classement
/// affiche vingt écussons, une composition vingt-deux visages : sur un
/// téléphone d'entrée de gamme, cela représente plusieurs dizaines de mégaoctets
/// de bitmaps décodés pour quelques milliers de pixels réellement peints.
///
/// Aucun ne mettait non plus en cache sur disque : revenir sur un écran
/// retéléchargeait tout. En Afrique de l'Ouest, où la donnée mobile se compte,
/// ce n'est pas un détail de confort.
///
/// Ce widget fait les deux, et rend l'oubli impossible : `cacheWidth` se
/// calcule ici, à partir de la taille demandée et de la densité de l'écran, et
/// non à chaque point d'appel où il finirait par manquer.
class ImageDistante extends StatelessWidget {
  /// Adresse de l'image. Vide ou nulle → [repli] directement.
  final String? url;

  /// Taille d'affichage. Sert aussi à décider la résolution de décodage : sans
  /// elle, on ne peut pas décoder plus petit, et on ne le fait pas.
  final double? largeur;
  final double? hauteur;

  final BoxFit fit;

  /// En-têtes HTTP, quand la source en exige (certains CDN d'actualités).
  final Map<String, String>? entetes;

  /// Ce qu'on montre en attendant, en cas d'échec, ou faute d'adresse.
  ///
  /// Un seul repli pour les trois cas : distinguer « en cours » de « échoué »
  /// sur une vignette de seize pixels produit un clignotement, pas une
  /// information.
  final Widget repli;

  const ImageDistante({
    super.key,
    required this.url,
    required this.repli,
    this.largeur,
    this.hauteur,
    this.fit = BoxFit.cover,
    this.entetes,
  });

  /// Nombre de pixels physiques à décoder pour [logique] pixels logiques.
  int? _pixels(double? logique, double densite) =>
      (logique == null || !logique.isFinite || logique <= 0)
          ? null
          : (logique * densite).round();

  @override
  Widget build(BuildContext context) {
    final adresse = url?.trim() ?? '';
    if (adresse.isEmpty) return repli;

    // `devicePixelRatio` et non un facteur fixe : décoder à 2× sur un écran 3×
    // rendrait les écussons visiblement flous, et à 3× sur un écran 1,5×
    // gaspillerait ce qu'on cherche à économiser.
    final densite = MediaQuery.devicePixelRatioOf(context);

    // Beaucoup d'images n'ont pas de taille explicite : un fond de carte, une
    // vignette qui remplit sa colonne. Exiger que chaque point d'appel la
    // connaisse, c'est garantir qu'un jour l'un d'eux se trompera ou l'oubliera.
    // On lit donc les contraintes de mise en page quand elles sont bornées.
    return LayoutBuilder(
      builder: (context, contraintes) {
        final l = largeur ?? (contraintes.hasBoundedWidth
            ? contraintes.maxWidth : null);
        final h = hauteur ?? (contraintes.hasBoundedHeight
            ? contraintes.maxHeight : null);

        return CachedNetworkImage(
          imageUrl:       adresse,
          width:          largeur,
          height:         hauteur,
          fit:            fit,
          httpHeaders:    entetes,
          memCacheWidth:  _pixels(l, densite),
          memCacheHeight: _pixels(h, densite),
          placeholder:    (_, _) => repli,
          errorWidget:    (_, _, _) => repli,
          // Pas de fondu : ces images sont des vignettes dans des listes, et
          // une animation par vignette transforme le défilement en
          // scintillement.
          fadeInDuration:  Duration.zero,
          fadeOutDuration: Duration.zero,
        );
      },
    );
  }
}
