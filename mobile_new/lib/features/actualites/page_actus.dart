import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/motion.dart';
import '../../core/widgets/image_distante.dart';
import '../../core/widgets/team_logo_widget.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/editorial_text.dart';
import '../../shared/providers/favoris_provider.dart';
import '../../shared/utils/retour.dart';
import 'actualites.dart';

/// La page Actus, au modèle de FotMob (vidéo du 17 octobre 2026, 1:44-2:45).
///
/// Un grand titre, des onglets texte qu'on fait glisser ; « Pour toi » ouvre
/// sur « Tendance » — une grande carte photo, puis des lignes, vignette à
/// gauche et titre à droite — et « Plus récent », en grandes cartes. Pendant
/// le chargement, des blocs gris scintillent ; les photos arrivent en fondu.
/// Un article s'ouvre en glissant depuis la droite (`PageArticle`).
///
/// « Pour toi » met en tête les résumés des matchs qu'on suit.
class PageActus extends ConsumerWidget {
  const PageActus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(toutesActualitesProvider);
    final toutes = etat.valueOrNull;
    final suivis = ref.watch(favorisProvider).valueOrNull?.matchIds ?? const <String>{};
    final aRedaction = toutes?.any((n) => familleActu(n) == FamilleActu.redaction) ?? false;

    final onglets = <(String, String, List<Map<String, dynamic>> Function(List<Map<String, dynamic>>), bool)>[
      ('pour-toi', tr(context, "Pour toi"), (l) => _pourToi(l, suivis), true),
      ('recent', tr(context, "Plus récent"), _parDate, false),
      ('resumes', tr(context, "Résumés"), (l) => _parDate(l).where((n) => familleActu(n) == FamilleActu.resume).toList(), false),
      ('medias', tr(context, "Médias"), (l) => _parDate(l).where((n) => familleActu(n) == FamilleActu.media).toList(), false),
      if (aRedaction)
        ('redaction', tr(context, "PronoWin"), (l) => _parDate(l).where((n) => familleActu(n) == FamilleActu.redaction).toList(), false),
    ];

    return DefaultTabController(
      key: ValueKey(onglets.length),
      length: onglets.length,
      child: Scaffold(
        backgroundColor: context.cl.surface,
        body: SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Grand titre ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(children: [
                IconButton(
                  tooltip: tr(context, "Retour"),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => retourOuAller(context, repli: '/home')),
                Expanded(child: Semantics(header: true, child: Text(tr(context, "Actualités"),
                  style: TextStyle(color: context.cl.textP, fontSize: 28, fontWeight: FontWeight.w800)))),
              ]),
            ),
            // ── Onglets texte, comme FotMob ────────────────────────────────
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: context.cl.textP, width: 2),
                borderRadius: BorderRadius.circular(2)),
              labelColor: context.cl.textP,
              unselectedLabelColor: context.cl.textM,
              labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              tabs: [for (final o in onglets) Tab(key: Key('onglet-actus-${o.$1}'), text: o.$2)],
            ),
            Expanded(child: etat.when(
              loading: () => const _Squelette(),
              error: (_, _) => _Erreur(onRetry: () => ref.invalidate(toutesActualitesProvider)),
              data: (liste) => TabBarView(children: [
                for (final o in onglets)
                  _Onglet(
                    actus: o.$3(liste),
                    tendance: o.$4,
                    onRefresh: () async {
                      ref.invalidate(toutesActualitesProvider);
                      await ref.read(toutesActualitesProvider.future)
                          .catchError((_) => <Map<String, dynamic>>[]);
                    },
                  ),
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _parDate(List<Map<String, dynamic>> l) {
    final copie = [...l];
    copie.sort((a, b) => (dateActu(b) ?? DateTime(2000)).compareTo(dateActu(a) ?? DateTime(2000)));
    return copie;
  }

  /// Les résumés des matchs suivis d'abord, puis tout le reste par date.
  static List<Map<String, dynamic>> _pourToi(List<Map<String, dynamic>> l, Set<String> suivis) {
    final tries = _parDate(l);
    bool suivi(Map<String, dynamic> n) => suivis.contains(n['match_id']);
    return [...tries.where(suivi), ...tries.where((n) => !suivi(n))];
  }
}

/// Ouvre un article et le marque comme lu.
void ouvrirActu(BuildContext context, WidgetRef ref, Map<String, dynamic> news) {
  HapticFeedback.selectionClick();
  ref.read(actualitesLuesProvider.notifier).marquer(news['id'] as String? ?? '');
  context.push('/actualites/article', extra: news);
}

class _Onglet extends ConsumerWidget {
  final List<Map<String, dynamic>> actus;
  final bool tendance;
  final Future<void> Function() onRefresh;
  const _Onglet({required this.actus, required this.tendance, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lues = ref.watch(actualitesLuesProvider);
    final enfants = <Widget>[];
    if (actus.isEmpty) {
      enfants.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Text(tr(context, "Aucune actualité pour l'instant."), textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textS))));
    } else if (tendance) {
      // « Tendance » : une grande carte et trois lignes ; puis « Plus récent ».
      enfants.add(_TitreSection(icone: Icons.show_chart_rounded, texte: tr(context, "Tendance")));
      enfants.add(_CarteActu(news: actus.first, lue: lues.contains(actus.first['id'])));
      for (final n in actus.skip(1).take(3)) {
        enfants.add(_LigneActu(news: n, lue: lues.contains(n['id'])));
      }
      if (actus.length > 4) {
        enfants.add(_TitreSection(icone: Icons.circle, petite: true, texte: tr(context, "Plus récent")));
        for (final n in actus.skip(4)) {
          enfants.add(_CarteActu(news: n, lue: lues.contains(n['id'])));
        }
      }
    } else {
      for (final n in actus) {
        enfants.add(familleActu(n) == FamilleActu.resume
            ? _CarteActu(news: n, lue: lues.contains(n['id']))
            : _LigneActu(news: n, lue: lues.contains(n['id'])));
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: enfants.length,
        itemBuilder: (context, i) => (context.animationsReduites || i > 8)
            ? enfants[i]
            // Entrée en cascade des premiers éléments, comme à l'ouverture de FotMob.
            : enfants[i].animate(delay: (i * 45).ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final IconData icone;
  final String texte;
  final bool petite;
  const _TitreSection({required this.icone, required this.texte, this.petite = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Semantics(header: true, child: Row(children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(color: context.cl.success, shape: BoxShape.circle),
        child: Icon(icone, color: Colors.white, size: petite ? 8 : 14)),
      const SizedBox(width: 8),
      Text(texte, style: TextStyle(color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
    ])),
  );
}

/// Un bloc gris : la place d'une photo pendant son chargement.
class _BlocGris extends StatelessWidget {
  final double? largeur, hauteur;
  final double rayon;
  const _BlocGris({this.largeur, this.hauteur, this.rayon = 10});
  @override
  Widget build(BuildContext context) => Container(
    width: largeur, height: hauteur,
    decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(rayon)));
}

/// La photo d'une actualité, ou — pour un résumé de match — ses deux logos et
/// le score.
class VisuelActu extends StatelessWidget {
  final Map<String, dynamic> news;
  final double largeur, hauteur;
  final bool compact;
  const VisuelActu({super.key, required this.news, required this.largeur, required this.hauteur, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final image = news['image_url'] as String?;
    if (image != null && image.isNotEmpty) {
      return ImageDistante(url: image, largeur: largeur, hauteur: hauteur,
        fondu: const Duration(milliseconds: 280),
        repli: _BlocGris(largeur: largeur, hauteur: hauteur, rayon: 0));
    }
    if (familleActu(news) == FamilleActu.resume) {
      final score = news['score'] as String?;
      final logo = compact ? hauteur * 0.36 : hauteur * 0.30;
      return ExcludeSemantics(child: Container(
        width: largeur, height: hauteur,
        decoration: BoxDecoration(gradient: LinearGradient(
          colors: [context.cl.success.withValues(alpha: 0.16), context.cl.surfaceD],
          begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TeamLogoWidget(url: news['logo_domicile'] as String?, size: logo),
          SizedBox(width: compact ? 6 : 18),
          if (score != null)
            Text(score, style: TextStyle(color: context.cl.textP, fontSize: compact ? 15 : 34,
              fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          SizedBox(width: compact ? 6 : 18),
          TeamLogoWidget(url: news['logo_exterieur'] as String?, size: logo),
        ]),
      ));
    }
    return Container(width: largeur, height: hauteur, color: context.cl.surfaceD,
      child: Icon(Icons.newspaper_rounded, color: context.cl.textM, size: hauteur * 0.3));
  }
}

/// « PronoWin · Ligue 1 · Il y a 2 h » — sous chaque titre.
class LigneSource extends StatelessWidget {
  final Map<String, dynamic> news;
  final bool dateLongue;
  const LigneSource({super.key, required this.news, this.dateLongue = false});

  @override
  Widget build(BuildContext context) {
    final date = dateActu(news);
    final morceaux = [
      sourceActu(news),
      if (familleActu(news) == FamilleActu.resume && (news['categorie'] as String?)?.isNotEmpty == true)
        news['categorie'] as String,
      dateLongue ? dateArticle(context, date) : ilYa(context, date),
    ].where((m) => m.isNotEmpty);
    return Row(children: [
      Container(
        width: 16, height: 16,
        decoration: BoxDecoration(
          color: familleActu(news) == FamilleActu.media ? context.cl.textM : context.cl.success,
          shape: BoxShape.circle),
        child: Icon(familleActu(news) == FamilleActu.media ? Icons.rss_feed_rounded : Icons.sports_soccer_rounded,
          size: 10, color: Colors.white)),
      const SizedBox(width: 6),
      Expanded(child: Text(morceaux.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.cl.textM, fontSize: dateLongue ? 14 : 12))),
    ]);
  }
}

/// La grande carte : photo pleine largeur, titre dessous.
class _CarteActu extends ConsumerWidget {
  final Map<String, dynamic> news;
  final bool lue;
  const _CarteActu({required this.news, required this.lue});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    button: true,
    child: InkWell(
      key: Key('actu-${news['id']}'),
      onTap: () => ouvrirActu(context, ref, news),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(aspectRatio: 16 / 9, child: LayoutBuilder(builder: (_, c) =>
              VisuelActu(news: news, largeur: c.maxWidth, hauteur: c.maxHeight))),
          ),
          const SizedBox(height: 10),
          Text(editorialField(news, 'titre'), maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: lue ? context.cl.textS : context.cl.textP,
              fontSize: 16, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 6),
          LigneSource(news: news),
        ]),
      ),
    ),
  );
}

/// La ligne : vignette à gauche, titre à droite.
class _LigneActu extends ConsumerWidget {
  final Map<String, dynamic> news;
  final bool lue;
  const _LigneActu({required this.news, required this.lue});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    button: true,
    child: InkWell(
      key: Key('actu-${news['id']}'),
      onTap: () => ouvrirActu(context, ref, news),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: VisuelActu(news: news, largeur: 124, hauteur: 78, compact: true)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editorialField(news, 'titre'), maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: lue ? context.cl.textS : context.cl.textP,
                fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 6),
            LigneSource(news: news),
          ])),
        ]),
      ),
    ),
  );
}

/// Pendant le chargement : la forme de la page, en gris qui scintille.
class _Squelette extends StatelessWidget {
  const _Squelette();
  @override
  Widget build(BuildContext context) {
    Widget ligne() => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        const _BlocGris(largeur: 124, hauteur: 78, rayon: 8),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          _BlocGris(hauteur: 14, rayon: 4),
          SizedBox(height: 8),
          _BlocGris(largeur: 160, hauteur: 14, rayon: 4),
          SizedBox(height: 10),
          _BlocGris(largeur: 110, hauteur: 10, rayon: 4),
        ])),
      ]));
    final contenu = ListView(
      key: const Key('actus-squelette'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      children: [
        const AspectRatio(aspectRatio: 16 / 9, child: _BlocGris()),
        const SizedBox(height: 12),
        const _BlocGris(hauteur: 16, rayon: 4),
        const SizedBox(height: 8),
        const _BlocGris(largeur: 220, hauteur: 16, rayon: 4),
        const SizedBox(height: 24),
        ligne(), ligne(), ligne(),
      ],
    );
    if (context.animationsReduites) return contenu;
    return contenu.animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1300.ms, color: context.cl.surface.withValues(alpha: 0.6));
  }
}

class _Erreur extends StatelessWidget {
  final VoidCallback onRetry;
  const _Erreur({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(tr(context, "Actualités momentanément indisponibles."),
        textAlign: TextAlign.center, style: TextStyle(color: context.cl.textS)),
      const SizedBox(height: 8),
      TextButton(onPressed: onRetry, child: Text(tr(context, "Réessayer"))),
    ]),
  ));
}
