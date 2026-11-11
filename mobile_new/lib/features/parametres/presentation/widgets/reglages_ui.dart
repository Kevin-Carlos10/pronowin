import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

// Les briques des Paramètres, au dessin de l'application 1xPartners
// (demande du 11 novembre 2026) : titres de section discrets en minuscules,
// cartes arrondies, une icône ronde d'une seule couleur par ligne, un statut
// « Activé / Pas activé » sous le titre plutôt qu'une phrase d'explication,
// et des sous-pages plutôt que des feuilles qui montent du bas.

/// Le titre d'une section : « Sécurité », « Paramètres de l'application ».
class EnTeteReglages extends StatelessWidget {
  final String titre;
  const EnTeteReglages(this.titre, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    child: Text(titre, style: TextStyle(
      color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w500)),
  );
}

/// Une carte de lignes, séparées d'un trait qui part du texte.
class CarteReglages extends StatelessWidget {
  final List<Widget> lignes;
  const CarteReglages(this.lignes, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(children: [
      for (var i = 0; i < lignes.length; i++) ...[
        if (i > 0) Divider(color: context.cl.border, height: 1, indent: 62),
        lignes[i],
      ],
    ]),
  );
}

/// L'icône d'une ligne : ronde, d'une seule couleur — rouge pour ce qui
/// détruit.
class IconeReglage extends StatelessWidget {
  final IconData icone;
  final bool danger;
  const IconeReglage(this.icone, {super.key, this.danger = false});

  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: danger ? context.cl.error.withValues(alpha: 0.12) : context.cl.surfaceD,
      shape: BoxShape.circle),
    child: Icon(icone, size: 20, color: danger ? context.cl.error : AppColors.primary),
  );
}

/// « ✓ Activé » en vert, « ✗ Pas activé » en rouge.
class StatutReglage extends StatelessWidget {
  final bool actif;
  final String texte;
  const StatutReglage({super.key, required this.actif, required this.texte});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(actif ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 13, color: actif ? context.cl.success : context.cl.error),
      const SizedBox(width: 4),
      Flexible(child: Text(texte, style: TextStyle(color: context.cl.textS, fontSize: 12))),
    ]),
  );
}

/// Le titre d'une ligne, et ce qui s'écrit dessous : un statut, ou une
/// valeur (« Sombre », « 323 Mo »).
class _TexteLigne extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final StatutReglage? statut;
  final bool danger;
  const _TexteLigne({required this.titre, this.sousTitre, this.statut, this.danger = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
    children: [
      Text(titre, style: TextStyle(
        color: danger ? context.cl.error : context.cl.textP,
        fontSize: 15, fontWeight: FontWeight.w500)),
      if (statut != null) statut!
      else if (sousTitre != null) Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(sousTitre!, style: TextStyle(
          color: danger ? context.cl.error.withValues(alpha: 0.7) : context.cl.textS, fontSize: 12))),
    ],
  );
}

/// Une ligne qui mène ailleurs : chevron à droite.
class LigneReglage extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String? sousTitre;
  final StatutReglage? statut;
  final VoidCallback onTap;
  final bool danger;
  const LigneReglage({super.key, required this.icone, required this.titre,
    this.sousTitre, this.statut, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          IconeReglage(icone, danger: danger),
          const SizedBox(width: 12),
          Expanded(child: _TexteLigne(titre: titre, sousTitre: sousTitre, statut: statut, danger: danger)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 20,
            color: danger ? context.cl.error.withValues(alpha: 0.6) : context.cl.textM),
        ]),
      ),
    ),
  );
}

/// Une ligne à interrupteur. Toute la ligne répond, pas seulement
/// l'interrupteur.
class LigneInterrupteur extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String? sousTitre;
  final StatutReglage? statut;
  final bool valeur;
  final ValueChanged<bool>? onChanged;
  /// Fonction absente de l'appareil : un tiret plutôt qu'un interrupteur
  /// mort, qu'on confondait avec un simple « éteint ».
  final bool indisponible;
  const LigneInterrupteur({super.key, required this.icone, required this.titre,
    this.sousTitre, this.statut, required this.valeur, required this.onChanged,
    this.indisponible = false});

  @override
  Widget build(BuildContext context) {
    final ligne = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(children: [
          IconeReglage(icone),
          const SizedBox(width: 12),
          Expanded(child: _TexteLigne(titre: titre, sousTitre: sousTitre, statut: statut)),
          if (indisponible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.do_not_disturb_on_outlined,
                color: context.cl.textM.withValues(alpha: 0.5), size: 20))
          else
            Switch(
              value: valeur,
              onChanged: onChanged == null ? null : (v) {
                HapticFeedback.selectionClick();
                onChanged!(v);
              },
              thumbColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? Colors.white : context.cl.textM),
              trackColor: WidgetStateProperty.resolveWith((s) {
                if (s.contains(WidgetState.disabled)) return context.cl.borderS.withValues(alpha: 0.4);
                if (s.contains(WidgetState.selected)) return AppColors.primary;
                return context.cl.borderS;
              }),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
        ]),
      ),
    );
    if (onChanged == null) return ligne;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged!(!valeur);
      },
      child: ligne,
    );
  }
}

/// Une option d'une liste de choix (thème, langue…) : le choix en cours en
/// couleur, coché à droite.
class LigneChoix extends StatelessWidget {
  final String titre;
  final bool choisi;
  final VoidCallback onTap;
  final Widget? avant;
  const LigneChoix({super.key, required this.titre, required this.choisi,
    required this.onTap, this.avant});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          if (avant != null) ...[avant!, const SizedBox(width: 12)],
          Expanded(child: Text(titre, style: TextStyle(
            color: choisi ? context.cl.accent : context.cl.textP,
            fontSize: 15, fontWeight: choisi ? FontWeight.w600 : FontWeight.w400))),
          if (choisi) const Icon(Icons.check_rounded, color: AppColors.primary, size: 22),
        ]),
      ),
    ),
  );
}

/// Le cadre d'une page de réglages : titre centré, retour, liste.
class PageReglages extends StatelessWidget {
  final String titre;
  final List<Widget> enfants;
  final VoidCallback? retour;
  const PageReglages({super.key, required this.titre, required this.enfants, this.retour});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: retour ?? () => Navigator.of(context).maybePop(),
      ),
      title: Text(titre, style: TextStyle(color: context.cl.textP, fontSize: 17, fontWeight: FontWeight.w600)),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 60),
      children: enfants,
    ),
  );
}
