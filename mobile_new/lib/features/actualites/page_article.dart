import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/editorial_text.dart';
import '../../shared/utils/retour.dart';
import 'actualites.dart';
import 'page_actus.dart';

/// Un article, au modèle de FotMob : la photo en pleine largeur, sous la
/// barre d'état ; deux boutons ronds, retour et partage, qui restent par-dessus
/// pendant la lecture ; le titre en gras, la source et l'heure ; le texte.
///
/// Un résumé de match mène à la fiche du match ; un titre de média, à son
/// article d'origine ; un article de la rédaction se lit ici en entier.
class PageArticle extends ConsumerWidget {
  final Map<String, dynamic> news;
  const PageArticle({super.key, required this.news});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final famille = familleActu(news);
    final id = news['id'] as String? ?? '';
    final complet = famille == FamilleActu.redaction
        ? ref.watch(articleRedactionProvider(id)).valueOrNull : null;
    final texte = complet != null
        ? _sansBalises(editorialField(complet, 'contenu'))
        : editorialField(news, 'resume');
    final paragraphes = texte.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final largeur = MediaQuery.sizeOf(context).width;
    final hauteurVisuel = largeur * 0.66;
    final haut = MediaQuery.paddingOf(context).top;
    final aPhoto = (news['image_url'] as String?)?.isNotEmpty == true;
    final aVisuel = aPhoto || famille == FamilleActu.resume;
    final matchId = news['match_id'] as String?;
    final source = news['source_url'] as String?;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: aPhoto ? SystemUiOverlayStyle.light : (context.cl.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
      child: Scaffold(
        backgroundColor: context.cl.surface,
        body: Stack(children: [
          CustomScrollView(slivers: [
            SliverToBoxAdapter(child: aVisuel
                ? VisuelActu(news: news, largeur: largeur, hauteur: hauteurVisuel + haut)
                : SizedBox(height: haut + 64)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              sliver: SliverList.list(children: [
                Semantics(header: true, child: Text(titreActu(news),
                  style: TextStyle(color: context.cl.textP, fontSize: 25, fontWeight: FontWeight.w800, height: 1.25))),
                const SizedBox(height: 12),
                LigneSource(news: news, dateLongue: true),
                const SizedBox(height: 18),
                for (final p in paragraphes) ...[
                  Text(p, style: TextStyle(color: context.cl.textP, fontSize: 17, height: 1.55)),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 10),
                // Ouvert depuis la fiche du match : il n'y renvoie pas.
                if (famille == FamilleActu.resume && matchId != null && matchId.isNotEmpty
                    && news['depuis_fiche'] != true)
                  FilledButton.icon(
                    key: const Key('actu-voir-match'),
                    onPressed: () => context.push('/pronostics/$matchId'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.sports_soccer_rounded, size: 18),
                    label: Text(tr(context, "Voir la fiche du match"),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  )
                else if (source != null && source.isNotEmpty)
                  FilledButton.icon(
                    key: const Key('actu-lire-original'),
                    onPressed: () => context.push('/navigateur', extra: {'url': source, 'title': editorialField(news, 'titre')}),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(famille == FamilleActu.media
                        ? tr(context, "Lire l'article sur {arg0}", [sourceActu(news)])
                        : tr(context, "Lire l'article complet"),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ]),
          // Les deux boutons ronds, posés sur la photo et fixes pendant la lecture.
          Positioned(top: haut + 8, left: 12,
            child: _BoutonRond(
              cle: const Key('article-retour'),
              icone: Icons.arrow_back_ios_new_rounded,
              libelle: tr(context, "Retour"),
              onTap: () => retourOuAller(context, repli: '/actualites'))),
          Positioned(top: haut + 8, right: 12,
            child: Builder(builder: (bouton) => _BoutonRond(
              cle: const Key('article-partager'),
              icone: Icons.ios_share_rounded,
              libelle: tr(context, "Partager"),
              onTap: () => _partager(bouton)))),
        ]),
      ),
    );
  }

  Future<void> _partager(BuildContext bouton) async {
    final lien = (news['source_url'] as String?)?.isNotEmpty == true
        ? news['source_url'] as String
        : AppConstants.siteUrl;
    Rect? origine;
    final boite = bouton.findRenderObject();
    if (boite is RenderBox && boite.hasSize && boite.attached) {
      origine = boite.localToGlobal(Offset.zero) & boite.size;
    }
    try {
      await Share.share('${editorialField(news, 'titre')}\n$lien', sharePositionOrigin: origine);
    } catch (_) {
      // Pas de feuille de partage disponible : rien de plus à faire.
    }
  }

  /// Le texte d'un article de la rédaction, sans balises.
  static String _sansBalises(String html) => html
      .replaceAll(RegExp(r'<\s*(br|/p|/div|/h\d|/li)\s*/?>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// La page de `/actualites/article` : l'article passé en paramètre, sinon
/// celui de `?id=`, sinon la page Actus — lien ouvert de l'extérieur, ou
/// version précédente du serveur.
Widget pageDeLArticle(Object? extra, Map<String, String> requete) =>
    extra is Map ? PageArticle(news: Map<String, dynamic>.from(extra))
    : (requete['id']?.isNotEmpty ?? false) ? PageArticleDepuisLien(id: requete['id']!)
    : const PageActus();

/// Un article ouvert par un lien, sans l'article lui-même : la notification
/// « Le résumé est prêt » (22 octobre 2026) mène à
/// `/actualites/article?id=resume_…`. On le cherche parmi les actualités ;
/// introuvable — il a quitté le fil —, c'est la page Actus.
class PageArticleDepuisLien extends ConsumerWidget {
  final String id;
  const PageArticleDepuisLien({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(toutesActualitesProvider);
    final trouve = etat.valueOrNull?.where((n) => n['id'] == id).firstOrNull;
    if (trouve != null) {
      // Lu, mais après la construction : un fournisseur ne change pas pendant.
      Future.microtask(() => ref.read(actualitesLuesProvider.notifier).marquer(id));
      return PageArticle(news: trouve);
    }
    if (etat.isLoading) {
      return Scaffold(
        backgroundColor: context.cl.surface,
        body: const Center(child: CircularProgressIndicator(key: Key('article-chargement'))));
    }
    return const PageActus();
  }
}

/// Bouton rond translucide, flouté, comme ceux de FotMob sur la photo.
class _BoutonRond extends StatelessWidget {
  final Key cle;
  final IconData icone;
  final String libelle;
  final VoidCallback onTap;
  const _BoutonRond({required this.cle, required this.icone, required this.libelle, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: libelle,
    child: ClipOval(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Material(
        color: Colors.black.withValues(alpha: 0.28),
        child: InkWell(
          key: cle,
          onTap: () { HapticFeedback.selectionClick(); onTap(); },
          child: SizedBox(width: 44, height: 44,
            child: ExcludeSemantics(child: Icon(icone, color: Colors.white, size: 20)))),
      ),
    )),
  );
}
