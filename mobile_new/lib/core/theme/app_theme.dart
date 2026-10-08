import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


// ─── Couleurs fixes (identiques dans les deux thèmes) ─────────────────────────
class AppColors {
  // Primaires
  static const primary      = Color(0xFFE8541A);
  /// Fond des boutons pleins : blanc dessus à 5,18:1 (voir plus bas).
  static const primaryBouton = Color(0xFFC2410C);
  static const primaryLight = Color(0xFFF5A623);

  // Sémantiques — les teintes vives, faites pour le thème sombre. Comme
  // couleur de texte en thème clair, elles échouent (vert sur blanc :
  // 2,28:1) : dans un écran, employer `context.cl.success` & co., qui
  // suivent le thème.
  static const success = Color(0xFF22C55E);
  static const error   = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info    = Color(0xFF3B82F6);

  // Fonds pleins portant du texte blanc, dans les deux thèmes (messages,
  // boutons). Blanc sur les teintes vives ci-dessus : 2,15 à 3,76:1.
  static const fondSucces = Color(0xFF15803D); // blanc dessus : 5,02:1
  static const fondErreur = Color(0xFFB91C1C); // 6,47:1
  static const fondAlerte = Color(0xFFB45309); // 5,02:1
  static const fondInfo   = Color(0xFF1D4ED8); // 6,70:1

  // Dégradés de marque. L'ancien, orange → jaune (#E8541A → #F5A623), portait
  // du texte blanc : 2,03:1 du côté jaune.
  /// Boutons et bandeaux qui portent du **texte** blanc : 5,02:1 au point le
  /// plus clair.
  static const degradeBouton = [Color(0xFFC2410C), Color(0xFFB45309)];
  /// Pastilles d'icône ou d'initiale : blanc ≥ 3,19:1, seuil des icônes et des
  /// grands caractères (3:1).
  static const degradeMarque = [primary, Color(0xFFD97706)];
  /// Boutons et pastilles verts qui portent du blanc : ≥ 5,02:1. Le vert vif
  /// (#22C55E, #34D399) n'en tenait que 2,28.
  static const degradeSucces = [Color(0xFF15803D), Color(0xFF166534)];

  // ─── Thème SOMBRE — gardés pour compatibilité ────────────────────────────
  static const background  = Color(0xFF0A0E1A);
  static const surface     = Color(0xFF151B2E);
  static const surfaceDeep = Color(0xFF0D1220);
  static const border      = Color(0xFF1E2A42);
  static const borderSoft  = Color(0xFF2A3050);

  static const textPrimary   = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF95A0B8);
  static const textMuted     = Color(0xFF7D8592);
}

// ─── Couleurs dynamiques selon le thème ───────────────────────────────────────
// Usage : context.cl.surface  /  context.cl.textPrimary  etc.
class AppCl {
  final bool isDark;
  const AppCl(this.isDark);

  // Fonds
  Color get bg        => isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF5F7FA);
  Color get surface   => isDark ? const Color(0xFF151B2E) : Colors.white;
  Color get surfaceD  => isDark ? const Color(0xFF0D1220) : const Color(0xFFF0F4F8);

  // Bordures
  Color get border    => isDark ? const Color(0xFF1E2A42) : const Color(0xFFE2E8F0);
  Color get borderS   => isDark ? const Color(0xFF2A3050) : const Color(0xFFEBEFF5);

  // Textes
  //
  // ── Pourquoi ces valeurs, et pas les précédentes ─────────────────────
  //
  // `textM` valait #4A5568 en sombre et #A0AEC0 en clair. Sur les fonds de
  // l'application, cela donnait **2,27:1** et **2,26:1** — la moitié du
  // minimum. Or ces gris ne servent pas qu'à décorer : ils portent les
  // libellés, les dates, les légendes et les onglets.
  //
  // La référence est WCAG AA, 4,5:1 pour du texte courant. C'est un repère
  // d'accessibilité sur ces couleurs-ci, pas une certification de
  // l'application.
  //
  // Relever `textM` le rapprochait de `textS` au point d'effacer la
  // hiérarchie : `textS` a donc été éclairci en sombre pour conserver un
  // écart comparable à celui du thème clair. `app_contraste_test.dart`
  // recalcule les rapports depuis ce fichier — une palette qui repasserait
  // sous le seuil fait tomber le banc.
  // Le noir et le blanc presque purs du texte d'Instagram (8 octobre 2026),
  // à la place d'un gris bleuté : le texte principal se détache mieux.
  Color get textP     => isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0C1014);
  Color get textS     => isDark ? const Color(0xFF95A0B8) : const Color(0xFF4A5568);
  Color get textM     => isDark ? const Color(0xFF7D8592) : const Color(0xFF666F7B);

  // Icône de section
  Color get sectionIcon => isDark ? const Color(0xFF8892AA) : const Color(0xFF4A5568);

  // États et accents : texte, icône, teinte de pastille.
  //
  // Les teintes vives d'`AppColors` étaient employées telles quelles dans les
  // deux thèmes. Sur fond blanc, comme texte, elles échouaient toutes : vert
  // 2,28:1, ambre 2,15:1, orange 3,4:1. Le thème clair a donc ses propres
  // valeurs, plus foncées, choisies pour tenir 4,5:1 **aussi sur leur propre
  // teinte** (pastille à 12–15 % sur blanc ou sur le fond) — c'est là que
  // ces couleurs portent leurs libellés les plus petits.
  //
  // Le thème sombre garde les vives, sauf trois : rouge, bleu et orange
  // tombaient à 3,9:1 sur leur propre pastille. Leurs variantes un ton plus
  // claires tiennent 5:1. Les aplats qui portent du blanc ne passent plus par
  // ces accesseurs mais par `AppColors.fond*` : un rouge plus clair y aurait
  // perdu du contraste.
  Color get success   => isDark ? const Color(0xFF22C55E) : const Color(0xFF14713A);
  Color get error     => isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
  Color get warning   => isDark ? const Color(0xFFF59E0B) : const Color(0xFF92400E);
  Color get info      => isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
  /// L'orange de la marque comme couleur de texte.
  Color get accent    => isDark ? const Color(0xFFF97316) : const Color(0xFFB4380A);
  /// L'or « Premium » comme couleur de texte.
  Color get dore      => isDark ? const Color(0xFFF5A623) : const Color(0xFF92400E);

  /// La version lisible, dans ce thème, d'une teinte vive d'[AppColors].
  ///
  /// Les tables de couleurs — catégories, niveaux, types de notification,
  /// forme V/N/D — restent écrites avec les constantes vives ; c'est à
  /// l'affichage qu'on passe par ici. En clair, un point vert #22C55E sur
  /// blanc fait 2,28:1, sous les 3:1 demandés aux éléments graphiques. Toute
  /// autre couleur revient telle quelle.
  Color lisible(Color vive) {
    if (vive == AppColors.success) return success;
    if (vive == AppColors.error) return error;
    if (vive == AppColors.warning) return warning;
    if (vive == AppColors.info) return info;
    if (vive == AppColors.primary) return accent;
    if (vive == AppColors.primaryLight) return dore;
    return vive;
  }

  // Aliases courts ↔ noms complets (compatibilité)
  Color get borderSoft  => borderS;
  Color get surfaceDeep => surfaceD;
}

extension AppThemeContext on BuildContext {
  AppCl get cl => AppCl(Theme.of(this).brightness == Brightness.dark);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Surface toujours sombre, quel que soit le thème choisi.
///
/// Certaines surfaces restent sombres en thème clair, par choix de marque :
/// le paywall, l'écran de mise à jour, les cartes phares de l'accueil, l'en-tête
/// du match, l'image de partage. Leurs textes, eux, suivaient le thème global :
/// en clair, un gris prévu pour un fond blanc se retrouvait sur du bleu nuit
/// (3,14:1), et les logos d'équipe de remplacement devenaient noirs sur noir.
///
/// Tout ce qui est construit par [builder] lit le thème sombre : `context.cl`,
/// les icônes, le texte par défaut et les composants Material. Le `context`
/// à employer est celui que reçoit [builder], pas celui de l'écran englobant.
///
/// Quand la surface passe sous la barre d'état (paywall, écran de mise à
/// jour), ses icônes restent claires : celles du thème clair seraient noires
/// sur noir.
class SurfaceSombre extends StatelessWidget {
  final WidgetBuilder builder;
  const SurfaceSombre({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness:     Brightness.dark,
        ),
        child: Theme(
          data: AppTheme.dark,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: AppColors.textPrimary),
            child: Builder(builder: builder),
          ),
        ),
      );
}

class AppTheme {
  AppTheme._();

  // ─── Jeux de couleurs ─────────────────────────────────────────────────────
  //
  // Tous les rôles Material 3 sont définis. `ColorScheme.light(...)` ne fixait
  // que primary, secondary, surface et error : le reste prenait des valeurs
  // par défaut — contours noirs (`outline` #000000 en clair, #FFFFFF en
  // sombre), et `surfaceContainer*` égaux à la surface, si bien que menus,
  // feuilles et dialogues avaient exactement la couleur des cartes posées
  // dessous.
  static const _schemaSombre = ColorScheme(
    brightness:              Brightness.dark,
    primary:                 AppColors.primary,      // 4,65:1 sur la surface
    onPrimary:               Color(0xFF111827),
    primaryContainer:        Color(0xFF7C2D12),
    onPrimaryContainer:      Color(0xFFFFEDD5),
    secondary:               AppColors.primaryLight,
    onSecondary:             Color(0xFF111827),
    secondaryContainer:      Color(0xFF78350F),
    onSecondaryContainer:    Color(0xFFFEF3C7),
    error:                   AppColors.error,
    onError:                 Colors.white,
    errorContainer:          Color(0xFF7F1D1D),
    onErrorContainer:        Color(0xFFFEE2E2),
    surface:                 AppColors.surface,
    onSurface:               AppColors.textPrimary,
    onSurfaceVariant:        AppColors.textSecondary,
    surfaceContainerLowest:  AppColors.background,
    surfaceContainerLow:     AppColors.surfaceDeep,
    surfaceContainer:        AppColors.surface,
    surfaceContainerHigh:    Color(0xFF1C2338),      // un cran au-dessus des cartes
    surfaceContainerHighest: Color(0xFF242C44),
    outline:                 Color(0xFF6B7690),      // 3,76:1 sur la surface
    outlineVariant:          AppColors.borderSoft,
    shadow:                  Colors.black,
    scrim:                   Colors.black,
    inverseSurface:          AppColors.textPrimary,
    onInverseSurface:        AppColors.surface,
    inversePrimary:          AppColors.primaryBouton,
    surfaceTint:             Colors.transparent,
  );

  static const _schemaClair = ColorScheme(
    brightness:              Brightness.light,
    // L'orange de marque (#E8541A) fait 3,4:1 sur blanc : il reste la
    // couleur des aplats, des icônes et des indicateurs ; le texte orange
    // passe par ce ton plus profond (5,98:1).
    primary:                 Color(0xFFB4380A),
    onPrimary:               Colors.white,
    primaryContainer:        Color(0xFFFFEDD5),
    onPrimaryContainer:      Color(0xFF7C2D12),
    secondary:               Color(0xFF92400E),
    onSecondary:             Colors.white,
    secondaryContainer:      Color(0xFFFEF3C7),
    onSecondaryContainer:    Color(0xFF78350F),
    error:                   Color(0xFFB91C1C),
    onError:                 Colors.white,
    errorContainer:          Color(0xFFFEE2E2),
    onErrorContainer:        Color(0xFF7F1D1D),
    surface:                 Colors.white,
    onSurface:               Color(0xFF1A202C),
    onSurfaceVariant:        Color(0xFF4A5568),
    surfaceContainerLowest:  Colors.white,
    surfaceContainerLow:     Color(0xFFF8FAFC),
    surfaceContainer:        Color(0xFFF5F7FA),
    surfaceContainerHigh:    Color(0xFFEEF2F6),
    surfaceContainerHighest: Color(0xFFE2E8F0),
    outline:                 Color(0xFF7C8798),      // 3,64:1 sur blanc
    outlineVariant:          Color(0xFFE2E8F0),
    shadow:                  Color(0xFF0F172A),
    scrim:                   Colors.black,
    inverseSurface:          Color(0xFF1A202C),
    onInverseSurface:        Color(0xFFF5F7FA),
    inversePrimary:          Color(0xFFFDBA74),
    surfaceTint:             Colors.transparent,
  );

  // ─── THÈME SOMBRE ─────────────────────────────────────────────────────────
  static final ThemeData dark = ThemeData(
    brightness:      Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: _schemaSombre,
    appBarTheme: const AppBarTheme(
      backgroundColor:  AppColors.background,
      elevation:        0,
      centerTitle:      false,
      titleTextStyle:   TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
      iconTheme:        IconThemeData(color: AppColors.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
    ),
    inputDecorationTheme: _champs(
      remplissage: AppColors.surfaceDeep,
      indice:      AppColors.textMuted,
      contour:     _schemaSombre.outline,
      erreur:      AppColors.error,
    ),
    elevatedButtonTheme: _boutonPlein,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.primary.withValues(alpha: 0.3) : AppColors.borderSoft),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor:         AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor:     AppColors.primary,
      indicatorSize:      TabBarIndicatorSize.tab,
      dividerColor:       AppColors.border,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5),
    // Menus, feuilles et dialogues un cran au-dessus des cartes : ils
    // avaient la couleur exacte de ce qu'ils recouvrent.
    popupMenuTheme:   const PopupMenuThemeData(color: Color(0xFF1C2338)),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF1C2338)),
    dialogTheme:      const DialogThemeData(backgroundColor: Color(0xFF1C2338)),
    textTheme: const TextTheme(
      titleLarge:  TextStyle(color: AppColors.textPrimary,   fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge:   TextStyle(color: AppColors.textPrimary,   fontSize: 15),
      bodyMedium:  TextStyle(color: AppColors.textSecondary, fontSize: 13),
      labelSmall:  TextStyle(color: AppColors.textMuted,     fontSize: 11),
    ),
  );

  // ─── THÈME CLAIR ──────────────────────────────────────────────────────────
  static final ThemeData light = ThemeData(
    brightness:      Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    colorScheme: _schemaClair,
    appBarTheme: const AppBarTheme(
      backgroundColor:  Colors.white,
      elevation:        0,
      centerTitle:      false,
      titleTextStyle:   TextStyle(color: Color(0xFF1A202C), fontSize: 17, fontWeight: FontWeight.w600),
      iconTheme:        IconThemeData(color: Color(0xFF4A5568)),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
      ),
    ),
    // Indice #A0AEC0 : 2,04:1 sur le champ. Contour #E2E8F0 : 1,2:1 —
    // le champ ne se distinguait pas de son fond.
    inputDecorationTheme: _champs(
      remplissage: const Color(0xFFF0F4F8),
      indice:      const Color(0xFF666F7B),              // 4,55:1 sur le champ
      contour:     _schemaClair.outline,                 // 3,29:1 sur le champ
      erreur:      _schemaClair.error,
    ),
    elevatedButtonTheme: _boutonPlein,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _schemaClair.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? Colors.white : _schemaClair.outline),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.primaryBouton : const Color(0xFFE2E8F0)),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? Colors.transparent : _schemaClair.outline),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor:            _schemaClair.primary,
      // #718096 : 4,0:1 sur blanc.
      unselectedLabelColor:  const Color(0xFF666F7B),
      indicatorColor:        AppColors.primary,
      indicatorSize:         TabBarIndicatorSize.tab,
      dividerColor:          const Color(0xFFE2E8F0),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 0.5),
    popupMenuTheme:   const PopupMenuThemeData(color: Colors.white),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white),
    dialogTheme:      const DialogThemeData(backgroundColor: Colors.white),
    textTheme: const TextTheme(
      titleLarge:  TextStyle(color: Color(0xFF1A202C), fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge:   TextStyle(color: Color(0xFF2D3748), fontSize: 15),
      bodyMedium:  TextStyle(color: Color(0xFF4A5568), fontSize: 13),
      // #718096 : 4,0:1 sur blanc.
      labelSmall:  TextStyle(color: Color(0xFF666F7B), fontSize: 11),
    ),
  );

  // ─── Composants communs aux deux thèmes ───────────────────────────────────
  static final _boutonPlein = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      // Une nuance plus sombre de l'orange de la marque pour le fond des
      // boutons : blanc sur #E8541A tombait à 3,68:1 pour un libellé de
      // 15 px, sous le seuil de 4,5:1 (constat M13). Sur #C2410C : 5,18:1.
      backgroundColor: AppColors.primaryBouton,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      elevation: 0,
    ),
  );

  /// Champs de saisie : la limite du champ doit se voir (3:1, WCAG 1.4.11),
  /// l'indice se lire (4,5:1).
  static InputDecorationTheme _champs({
    required Color remplissage,
    required Color indice,
    required Color contour,
    required Color erreur,
  }) {
    OutlineInputBorder bord(Color c, double l) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: l),
        );
    return InputDecorationTheme(
      filled:         true,
      fillColor:      remplissage,
      hintStyle:      TextStyle(color: indice, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border:             bord(contour, 1),
      enabledBorder:      bord(contour, 1),
      focusedBorder:      bord(AppColors.primary, 1.5),
      errorBorder:        bord(erreur, 1),
      focusedErrorBorder: bord(erreur, 1.5),
    );
  }
}
