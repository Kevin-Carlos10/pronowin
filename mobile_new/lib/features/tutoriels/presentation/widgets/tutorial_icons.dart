import 'package:flutter/material.dart';

/// Icône de catégorie de tutoriel.
///
/// Vit dans la couche présentation, et non dans `TutorialCategoryInfo` :
/// l'entité de domaine est du Dart pur, sans dépendance à Flutter. Elle garde
/// donc ses libellés, et c'est ici qu'on décide du rendu.
///
/// Les emoji qu'on remplace (🎯 💰 🧠 📊 ♟️) ne portaient aucune information
/// que le libellé juste à côté ne disait déjà, et leur rendu variait d'un
/// appareil à l'autre.
IconData tutorialCategoryIcon(String? category) {
  switch ((category ?? '').toLowerCase()) {
    case 'valuebet':
      return Icons.track_changes_rounded;
    case 'bankroll':
      return Icons.savings_rounded;
    case 'martingale':
      return Icons.autorenew_rounded;
    case 'trading':
      return Icons.bolt_rounded;
    case 'psychology':
    case 'psychologie':
      return Icons.psychology_rounded;
    case 'statistics':
    case 'analyse':
      return Icons.insights_rounded;
    case 'strategie':
      return Icons.account_tree_rounded;
    case '':
      return Icons.apps_rounded; // « Toutes les catégories »
    default:
      return Icons.menu_book_rounded;
  }
}
