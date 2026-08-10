import 'dart:ui';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Pays africains francophones les plus utilisés par nos utilisateurs —
/// épinglés en tête de la liste exhaustive (recherche disponible pour tous les autres).
const kFavoriteCountryCodes = ['BF', 'CI', 'SN', 'ML', 'GN', 'FR'];

/// Pays proposé par défaut dans les formulaires : celui de la région du
/// téléphone. L'ancienne valeur codée en dur (« BF ») enregistrait tous les
/// utilisateurs comme burkinabè, y compris ceux qui ne touchaient jamais au
/// sélecteur. Repli sur BF si le système ne déclare aucune région ou si elle
/// est inconnue de la base.
Country deviceDefaultCountry() {
  final region = PlatformDispatcher.instance.locale.countryCode;
  if (region != null && region.isNotEmpty) {
    final c = CountryService().findByCode(region);
    if (c != null) return c;
  }
  return CountryService().findByCode('BF')!;
}

/// Pastille compacte (drapeau + indicatif) qui ouvre le sélecteur de pays
/// exhaustif (tous les pays ISO, avec recherche) au tap.
class CountryPillSelector extends StatelessWidget {
  final Country country;
  final ValueChanged<Country> onSelect;
  const CountryPillSelector({super.key, required this.country, required this.onSelect});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      HapticFeedback.selectionClick();
      final picked = await showModalBottomSheet<Country>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _CountrySheet(selected: country),
      );
      if (picked != null) onSelect(picked);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cl.borderSoft, width: 0.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(country.flagEmoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 6),
        Text('+${country.phoneCode}', style: const TextStyle(
          color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 4),
        Icon(Icons.arrow_drop_down_rounded, color: context.cl.textM, size: 18),
      ]),
    ),
  );
}

// ─── Feuille de sélection ─────────────────────────────────────────────────────

/// Sélecteur maison plutôt que `showCountryPicker` : le paquet fige la
/// disposition de chaque ligne (drapeau, indicatif, nom collés à gauche), sans
/// en-tête ni séparation entre les pays épinglés et le reste. On réutilise sa
/// base de données (`CountryService`) et ses traductions, mais on maîtrise le
/// rendu : indicatif aligné à droite en colonne régulière, sections nommées,
/// pays courant mis en évidence.
class _CountrySheet extends StatefulWidget {
  final Country selected;
  const _CountrySheet({required this.selected});

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _searchCtrl = TextEditingController();
  late final List<Country> _all = CountryService().getAll();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Nom traduit selon la locale de l'app (délégué `CountryLocalizations`),
  /// avec repli sur le nom anglais du paquet.
  String _name(Country c) =>
      CountryLocalizations.of(context)?.countryName(countryCode: c.countryCode)
      ?? c.name;

  /// Comparaison insensible aux accents : taper « senegal » doit trouver
  /// « Sénégal », et le tri alphabétique doit placer « Åland » près de « A ».
  static String _fold(String s) {
    const from = 'àâäáãåçèéêëìíîïñòóôöõùúûüýÿœæ';
    const to   = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  bool _matches(Country c) {
    if (_query.isEmpty) return true;
    final q = _fold(_query);
    return _fold(_name(c)).contains(q)
        || _fold(c.name).contains(q)
        || c.phoneCode.contains(q)
        || c.countryCode.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final matching = _all.where(_matches).toList()
      ..sort((a, b) => _fold(_name(a)).compareTo(_fold(_name(b))));

    // Les pays épinglés ne forment une section distincte que hors recherche :
    // pendant une recherche, l'utilisateur veut une liste unique de résultats.
    final searching = _query.isNotEmpty;
    final favorites = searching
        ? const <Country>[]
        : [
            for (final code in kFavoriteCountryCodes)
              ...matching.where((c) => c.countryCode == code),
          ];
    final others = searching
        ? matching
        : matching.where((c) => !kFavoriteCountryCodes.contains(c.countryCode)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(children: [
          // Poignée
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: context.cl.border,
              borderRadius: BorderRadius.circular(2)),
          ),

          // Titre + compteur
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Indicatif du pays',
                    style: TextStyle(
                      color: context.cl.textP,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text('${_all.length} pays disponibles',
                    style: TextStyle(color: context.cl.textM, fontSize: 12)),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: context.cl.textM, size: 22),
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // Recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: TextStyle(color: context.cl.textP, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Rechercher un pays ou un indicatif',
                hintStyle: TextStyle(color: context.cl.textM, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: context.cl.textM, size: 20),
                suffixIcon: _query.isEmpty ? null : IconButton(
                  icon: Icon(Icons.close_rounded, color: context.cl.textM, size: 18),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
                filled: true,
                fillColor: context.cl.surfaceD,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.cl.borderSoft, width: 0.5)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.2)),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: matching.isEmpty
              ? _EmptyResults(query: _query)
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    if (favorites.isNotEmpty) ...[
                      const _SectionLabel('Fréquents'),
                      for (final c in favorites)
                        _CountryTile(
                          country: c,
                          label: _name(c),
                          isSelected: c.countryCode == widget.selected.countryCode,
                          onTap: () => Navigator.pop(context, c)),
                      const SizedBox(height: 10),
                    ],
                    if (others.isNotEmpty) ...[
                      _SectionLabel(searching
                        ? '${others.length} résultat${others.length > 1 ? 's' : ''}'
                        : 'Tous les pays'),
                      for (final c in others)
                        _CountryTile(
                          country: c,
                          label: _name(c),
                          isSelected: c.countryCode == widget.selected.countryCode,
                          onTap: () => Navigator.pop(context, c)),
                    ],
                  ],
                ),
          ),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(text.toUpperCase(),
      style: TextStyle(
        color: context.cl.textM,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9)),
  );
}

class _CountryTile extends StatelessWidget {
  final Country country;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _CountryTile({
    required this.country,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        // 56px de haut : confortable au pouce sur une liste longue.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        color: isSelected
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
        child: Row(children: [
          // Drapeau dans un cadre arrondi : les emojis drapeaux ont des
          // largeurs variables selon la plateforme, le cadre fixe aligne la
          // colonne des noms.
          Container(
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: context.cl.borderSoft, width: 0.5)),
            child: Text(country.flagEmoji, style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? AppColors.primary : context.cl.textP,
                fontSize: 14.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
          ),
          const SizedBox(width: 10),
          // Indicatif aligné à droite, largeur fixe → colonne régulière.
          SizedBox(
            width: 58,
            child: Text('+${country.phoneCode}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isSelected ? AppColors.primary : context.cl.textS,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          SizedBox(
            width: 26,
            child: isSelected
              ? const Icon(Icons.check_circle_rounded,
                  color: AppColors.primary, size: 18)
              : null,
          ),
        ]),
      ),
    ),
  );
}

class _EmptyResults extends StatelessWidget {
  final String query;
  const _EmptyResults({required this.query});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.travel_explore_rounded, color: context.cl.textM, size: 40),
      const SizedBox(height: 14),
      Text('Aucun pays trouvé',
        style: TextStyle(
          color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Rien ne correspond à « $query ». Essaie le nom du pays ou son indicatif.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.cl.textM, fontSize: 12.5, height: 1.4)),
    ]),
  );
}
