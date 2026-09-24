import 'package:flutter/material.dart';


// ─── Couleurs fixes (identiques dans les deux thèmes) ─────────────────────────
class AppColors {
  // Primaires
  static const primary      = Color(0xFFE8541A);
  /// Fond des boutons pleins : blanc dessus à 5,18:1 (voir plus bas).
  static const primaryBouton = Color(0xFFC2410C);
  static const primaryLight = Color(0xFFF5A623);

  // Sémantiques
  static const success = Color(0xFF22C55E);
  static const error   = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info    = Color(0xFF3B82F6);

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
  Color get textP     => isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1A202C);
  Color get textS     => isDark ? const Color(0xFF95A0B8) : const Color(0xFF4A5568);
  Color get textM     => isDark ? const Color(0xFF7D8592) : const Color(0xFF666F7B);

  // Icône de section
  Color get sectionIcon => isDark ? const Color(0xFF8892AA) : const Color(0xFF4A5568);

  // Aliases courts ↔ noms complets (compatibilité)
  Color get borderSoft  => borderS;
  Color get surfaceDeep => surfaceD;
}

extension AppThemeContext on BuildContext {
  AppCl get cl => AppCl(Theme.of(this).brightness == Brightness.dark);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  AppTheme._();

  // ─── THÈME SOMBRE ─────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
    brightness:      Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.primary,
      secondary: AppColors.primaryLight,
      surface:   AppColors.surface,
      error:     AppColors.error,
    ),
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
    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   AppColors.surfaceDeep,
      hintStyle:   const TextStyle(color: AppColors.textMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderSoft, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderSoft, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
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
    ),
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
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5),
    textTheme: const TextTheme(
      titleLarge:  TextStyle(color: AppColors.textPrimary,   fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge:   TextStyle(color: AppColors.textPrimary,   fontSize: 15),
      bodyMedium:  TextStyle(color: AppColors.textSecondary, fontSize: 13),
      labelSmall:  TextStyle(color: AppColors.textMuted,     fontSize: 11),
    ),
  );

  // ─── THÈME CLAIR ──────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    brightness:      Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    colorScheme: const ColorScheme.light(
      primary:   AppColors.primary,
      secondary: AppColors.primaryLight,
      surface:   Colors.white,
      error:     AppColors.error,
    ),
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
    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   const Color(0xFFF0F4F8),
      hintStyle:   const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
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
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.primary : Colors.grey),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.shade300),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor:            AppColors.primary,
      unselectedLabelColor:  Color(0xFF718096),
      indicatorColor:        AppColors.primary,
      indicatorSize:         TabBarIndicatorSize.tab,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 0.5),
    textTheme: const TextTheme(
      titleLarge:  TextStyle(color: Color(0xFF1A202C), fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge:   TextStyle(color: Color(0xFF2D3748), fontSize: 15),
      bodyMedium:  TextStyle(color: Color(0xFF4A5568), fontSize: 13),
      labelSmall:  TextStyle(color: Color(0xFF718096), fontSize: 11),
    ),
  );
}
