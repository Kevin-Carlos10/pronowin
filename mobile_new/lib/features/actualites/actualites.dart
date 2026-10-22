import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/dio_client.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/editorial_text.dart';
import '../accueil/presentation/providers/accueil_provider.dart';

/// Les actualités, hors de l'accueil (20 octobre 2026) : la page Actus au
/// style FotMob, la page d'un article, et le badge des non-lues dans Compte.
///
/// Une actualité est un `Map` tel que le serveur le sert (`/actualites`) :
/// résumé de match rédigé par le serveur, article de la rédaction, ou titre
/// d'un média (flux RSS) avec son lien.

enum FamilleActu { resume, media, redaction }

FamilleActu familleActu(Map<String, dynamic> n) =>
    n['type'] == 'resume_match' ? FamilleActu.resume
    : n['from_rss'] == true      ? FamilleActu.media
    : FamilleActu.redaction;

/// Un avant-match (22 octobre 2026) : article de match lui aussi, écrit la
/// veille. Le serveur le sert avec le type des résumés — les versions 1.0.25
/// à 1.0.28 lui donnent ainsi logos et « Voir le match » — et `genre`.
bool estAvantMatch(Map<String, dynamic> n) => n['genre'] == 'avant_match';

/// Le titre affiché, sans « Avant-match : » : l'étiquette de la carte le dit
/// déjà (`LigneSource`).
String titreActu(Map<String, dynamic> n) {
  final titre = editorialField(n, 'titre');
  if (!estAvantMatch(n)) return titre;
  return titre.replaceFirst(RegExp(r'^(Avant-match|Preview)\s*:\s*'), '');
}

/// Le centre du visuel d'un article de match : le score d'un résumé, « VS »
/// pour un avant-match.
String? centreVisuelMatch(Map<String, dynamic> n) =>
    (n['score'] as String?) ?? (estAvantMatch(n) ? 'VS' : null);

/// Toutes les actualités, pour la page Actus : jusqu'à 50 (l'accueil en lit
/// 20). Un serveur qui ne connaît pas `limite` en rend 20.
final toutesActualitesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.read(dioProvider).get('/actualites', queryParameters: {'limite': 50});
  return ((r.data as List<dynamic>?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

/// Le texte complet d'un article de la rédaction (la liste n'en donne que
/// l'extrait).
final articleRedactionProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  try {
    final r = await ref.read(dioProvider).get('/actualites/$id');
    return Map<String, dynamic>.from(r.data as Map);
  } catch (_) {
    return null;
  }
});

/// Les actualités déjà ouvertes, partagées par l'accueil, la page Actus et le
/// badge de Compte. Même clé qu'avant (`news_read_ids`) : ce qu'on a lu le
/// reste après la mise à jour.
class ActualitesLues extends StateNotifier<Set<String>> {
  ActualitesLues() : super(const {}) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = {...state, ...(p.getStringList(_cle) ?? const [])};
    });
  }
  static const _cle = 'news_read_ids';

  Future<void> marquer(String id) async {
    if (id.isEmpty || state.contains(id)) return;
    state = {...state, id};
    final p = await SharedPreferences.getInstance();
    // Les 300 dernières : la liste ne doit pas grossir sans fin.
    final liste = state.toList();
    await p.setStringList(_cle, liste.length > 300 ? liste.sublist(liste.length - 300) : liste);
  }
}

final actualitesLuesProvider =
    StateNotifierProvider<ActualitesLues, Set<String>>((ref) => ActualitesLues());

/// Le nombre d'actualités de l'accueil pas encore ouvertes : le badge du
/// raccourci « Actualités » de Compte.
final actualitesNonLuesProvider = Provider.autoDispose<int>((ref) {
  final actus = ref.watch(actualitesProvider).valueOrNull ?? const [];
  final lues = ref.watch(actualitesLuesProvider);
  return actus.where((n) => !lues.contains(n['id'] as String? ?? '')).length;
});

DateTime? dateActu(Map<String, dynamic> n) =>
    DateTime.tryParse(n['created_at'] as String? ?? '')?.toLocal();

/// « Il y a 2 h » — calculé ici, dans la langue de l'application : le texte
/// `date` du serveur est toujours en français.
String ilYa(BuildContext context, DateTime? date, {DateTime? maintenant}) {
  if (date == null) return '';
  final ecart = (maintenant ?? DateTime.now()).difference(date);
  if (ecart.inMinutes < 2) return tr(context, "À l'instant");
  if (ecart.inMinutes < 60) return tr(context, "Il y a {arg0} min", [ecart.inMinutes]);
  if (ecart.inHours < 24) return tr(context, "Il y a {arg0} h", [ecart.inHours]);
  if (ecart.inDays == 1) return tr(context, "Hier");
  if (ecart.inDays < 7) return tr(context, "Il y a {arg0} j", [ecart.inDays]);
  return DateFormat.MMMd(AppStrings.of(context).locale.languageCode).format(date);
}

/// « 20 oct. 2026 à 08:12 » — l'en-tête d'un article.
String dateArticle(BuildContext context, DateTime? date) {
  if (date == null) return '';
  final langue = AppStrings.of(context).locale.languageCode;
  return tr(context, "{arg0} à {arg1}",
      [DateFormat.yMMMd(langue).format(date), DateFormat.Hm(langue).format(date)]);
}

/// Qui signe : PronoWin pour un résumé ou un article de la rédaction, le média
/// pour un titre de flux.
String sourceActu(Map<String, dynamic> n) => switch (familleActu(n)) {
  FamilleActu.media => (n['source'] as String?) ?? (n['categorie'] as String?) ?? '',
  _ => 'PronoWin',
};
