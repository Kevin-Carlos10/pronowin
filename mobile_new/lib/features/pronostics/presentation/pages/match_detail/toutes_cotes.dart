// Tous les marchés cotés d'un match — onglet « Cotes ».
//
// `part` et non un fichier autonome : toutes ces classes sont privées à
// la bibliothèque (préfixe `_`) et le resteront. Un import classique aurait
// imposé de les rendre publiques, donc visibles depuis n'importe où.
part of '../match_detail_page.dart';

/// Les familles de marchés, pour trier une liste d'une cinquantaine.
enum _FamilleMarche { principaux, buts, miTemps, corners, tirs }

const _marchesPrincipaux = {
  'match winner', 'double chance', 'both teams score', 'goals over/under',
  'asian handicap', 'exact score', 'home/away',
};

_FamilleMarche _familleDe(String nom) {
  final n = nom.toLowerCase();
  if (n.contains('corner')) return _FamilleMarche.corners;
  if (n.contains('shot')) return _FamilleMarche.tirs;
  if (_marchesPrincipaux.contains(n)) return _FamilleMarche.principaux;
  if (RegExp(r'half|ht/ft').hasMatch(n)) return _FamilleMarche.miTemps;
  return _FamilleMarche.buts;
}

/// Un marché prêt à afficher : libellés traduits, cotes dans l'ordre du
/// fournisseur.
typedef _MarcheAffiche = ({String cle, String nom, _FamilleMarche famille, List<(String, double)> cotes});

/// Les marchés que l'écran sait nommer, dans les deux langues.
///
/// Un marché dont le nom ou l'une des valeurs manque au catalogue est écarté
/// en entier : « Corners Race To » ou « Draw 3 » en anglais au milieu d'un
/// écran français se liraient comme une erreur, et un marché amputé d'une
/// valeur ne dirait plus la même chose.
List<_MarcheAffiche> _marchesAffichables(List<MarcheCote> marches, MatchEntity match,
    {required String langue, required bool sans1x2}) {
  final sortie = <_MarcheAffiche>[];
  for (final m in marches) {
    // Le 1X2 du pronostic est déjà dans le bandeau, juste au-dessus.
    if (sans1x2 && m.nom == 'Match Winner') continue;
    final nom = FootballLabels.market(m.nom, language: langue);
    if (!nom.known) continue;
    final cotes = <(String, double)>[];
    for (final c in m.cotes) {
      final v = FootballLabels.selection(c.valeur, language: langue,
        home: match.homeTeam, away: match.awayTeam);
      if (!v.known) break;
      cotes.add((v.text, c.cote));
    }
    if (cotes.length != m.cotes.length) continue;
    sortie.add((cle: m.nom, nom: nom.text, famille: _familleDe(m.nom), cotes: cotes));
  }
  return sortie;
}

/// Tous les marchés du match, sous le bandeau du 1X2 — comme Sofascore et
/// 1xBet, qui en montrent une cinquantaine quand la fiche s'arrêtait à trois
/// cotes.
///
/// Lecture seule et sans marque : la même règle que le bandeau neutre. Les
/// cotes sont une information ; un lien vers un bookmaker n'a pas sa place
/// partout.
class _ToutesLesCotes extends ConsumerStatefulWidget {
  final MatchEntity match;
  final bool sans1x2;
  const _ToutesLesCotes({required this.match, required this.sans1x2});
  @override
  ConsumerState<_ToutesLesCotes> createState() => _ToutesLesCotesState();
}

class _ToutesLesCotesState extends ConsumerState<_ToutesLesCotes> {
  _FamilleMarche? _famille;
  final _ouverts = <String>{};
  bool _premiersOuverts = false;

  String _titre(BuildContext context, _FamilleMarche? f) => switch (f) {
    null                       => tr(context, "Tous"),
    _FamilleMarche.principaux  => tr(context, "Principaux"),
    _FamilleMarche.buts        => tr(context, "Buts"),
    _FamilleMarche.miTemps     => tr(context, "Mi-temps"),
    _FamilleMarche.corners     => tr(context, "Corners"),
    _FamilleMarche.tirs        => tr(context, "Tirs"),
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cotesMarchesProvider(widget.match.id));
    final langue = AppStrings.of(context).locale.languageCode;

    if (!async.hasValue) {
      if (async.isLoading) {
        return Padding(
          padding: const EdgeInsets.only(top: 16), child: _H2HLoading());
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          Expanded(child: Text(tr(context, "Les autres marchés sont momentanément indisponibles."),
            style: TextStyle(color: context.cl.textS, fontSize: 12))),
          TextButton(
            onPressed: () => ref.invalidate(cotesMarchesProvider(widget.match.id)),
            child: Text(tr(context, "Réessayer"))),
        ]),
      );
    }

    final tous = _marchesAffichables(async.value!, widget.match,
      langue: langue, sans1x2: widget.sans1x2);
    if (tous.isEmpty) return const SizedBox.shrink();

    // Les trois premiers ouverts d'office : le reste se déplie à la demande,
    // sans quoi cinquante grilles de cotes se suivraient sur dix écrans.
    if (!_premiersOuverts) {
      _ouverts.addAll(tous.take(3).map((m) => m.cle));
      _premiersOuverts = true;
    }

    final familles = [
      for (final f in _FamilleMarche.values)
        if (tous.any((m) => m.famille == f)) f,
    ];
    final famille = familles.contains(_famille) ? _famille : null;
    final visibles = famille == null ? tous : tous.where((m) => m.famille == famille).toList();

    return Padding(
      padding: EdgeInsets.only(top: widget.sans1x2 ? 20 : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr(context, "Tous les marchés"),
            style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700))),
          Text('${tous.length}',
            style: TextStyle(color: context.cl.textM, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (familles.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in <_FamilleMarche?>[null, ...familles])
              ChoiceChip(
                key: Key('cotes-famille-${f?.name ?? 'tous'}'),
                label: Text(_titre(context, f)),
                selected: f == famille,
                onSelected: (_) => setState(() => _famille = f),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: f == famille ? FontWeight.w700 : FontWeight.w500,
                  color: f == famille ? context.cl.textP : context.cl.textS),
                selectedColor: context.cl.textP.withValues(alpha: 0.10),
                side: BorderSide(color: f == famille
                    ? context.cl.textP.withValues(alpha: 0.35)
                    : context.cl.borderSoft),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
        const SizedBox(height: 12),
        for (final m in visibles) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CarteMarche(
            marche: m,
            ouvert: _ouverts.contains(m.cle),
            basculer: () => setState(() =>
              _ouverts.contains(m.cle) ? _ouverts.remove(m.cle) : _ouverts.add(m.cle)),
          ),
        ),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 13, color: context.cl.textM),
          const SizedBox(width: 6),
          Expanded(child: Text(
            tr(context, "Cotes indicatives, actualisées toutes les cinq minutes jusqu'au coup d'envoi."),
            style: TextStyle(color: context.cl.textM, fontSize: 11, height: 1.3))),
        ]),
      ]),
    );
  }
}

/// Un marché repliable : son nom, puis ses cotes en grille.
class _CarteMarche extends StatelessWidget {
  final _MarcheAffiche marche;
  final bool ouvert;
  final VoidCallback basculer;
  const _CarteMarche({required this.marche, required this.ouvert, required this.basculer});

  /// Trois colonnes pour un 1X2 ou une grille de scores, deux pour les
  /// marchés qui vont par paires (plus/moins, oui/non, handicap).
  static int colonnes(List<(String, double)> cotes) {
    final n = cotes.length;
    if (n == 3 || n == 9) return 3;
    if (cotes.every((c) => RegExp(r'^\d+\s*[-:]\s*\d+$').hasMatch(c.$1))) return 3;
    return n.isEven ? 2 : 3;
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.borderSoft, width: 0.8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        child: InkWell(
          key: Key('marche-${marche.cle}'),
          borderRadius: BorderRadius.circular(14),
          onTap: basculer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Expanded(child: Text(marche.nom,
                style: TextStyle(color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600))),
              AnimatedRotation(
                turns: ouvert ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: context.cl.textM)),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: !ouvert ? const SizedBox(width: double.infinity) : Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: LayoutBuilder(builder: (context, contraintes) {
            final n = colonnes(marche.cotes);
            final largeur = (contraintes.maxWidth - 8 * (n - 1)) / n;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (libelle, cote) in marche.cotes)
                SizedBox(width: largeur, child: _PastilleCote(libelle: libelle, cote: cote)),
            ]);
          }),
        ),
      ),
    ]),
  );
}

class _PastilleCote extends StatelessWidget {
  final String libelle;
  final double cote;
  const _PastilleCote({required this.libelle, required this.cote});

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, "{arg0}, cote {arg1}", [libelle, cote.toStringAsFixed(2)]),
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.cl.surfaceDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.cl.borderSoft, width: 0.5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(libelle,
          textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.2)),
        const SizedBox(height: 3),
        Text(cote.toStringAsFixed(2),
          style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}
