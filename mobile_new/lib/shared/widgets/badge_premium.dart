import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

/// Le badge bleu des membres Premium, à côté de leur nom — comme le badge de
/// vérification d'Instagram (demande du 20 octobre 2026).
///
/// Un sceau bleu, une coche blanche. L'icône Material `verified` laisse la
/// coche transparente : sur un fond sombre, elle prendrait la couleur du fond.
/// Un disque blanc posé dessous la rend blanche partout.
///
/// Utilisé dans les commentaires, le classement et la page Compte.
const Color bleuBadgePremium = Color(0xFF0095F6);

class BadgePremium extends StatelessWidget {
  final double taille;
  const BadgePremium({super.key, this.taille = 14});

  @override
  Widget build(BuildContext context) {
    final libelle = tr(context, "Membre Premium");
    return Tooltip(
      message: libelle,
      child: Semantics(
        label: libelle,
        child: ExcludeSemantics(
          child: SizedBox(
            width: taille, height: taille,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: taille * 0.55, height: taille * 0.55,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
              Icon(Icons.verified, size: taille, color: bleuBadgePremium),
            ]),
          ),
        ),
      ),
    );
  }
}
