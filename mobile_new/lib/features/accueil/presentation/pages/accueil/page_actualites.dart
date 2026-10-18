// Page « Actualités » — toutes les actualités, filtrables (18 octobre 2026).
//
// `part` de l'accueil, comme la section qu'elle prolonge : elle reprend ses
// cartes et sa fiche de lecture, privées à la bibliothèque.
part of '../accueil_page.dart';

/// Toutes les actualités : résumés de match (rédigés par le serveur), articles
/// de la rédaction et titres des médias. L'accueil n'en montrait que quatre,
/// dépliables sur place ; FotMob en fait un écran.
final toutesActualitesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // `limite` : un serveur qui ne le connaît pas encore en rend vingt.
  final r = await ref.read(dioProvider).get('/actualites', queryParameters: {'limite': 50});
  return ((r.data as List<dynamic>?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

enum _FiltreActus { tout, resumes, medias, redaction }

_FiltreActus _familleActu(Map<String, dynamic> n) =>
    n['type'] == 'resume_match' ? _FiltreActus.resumes
    : n['from_rss'] == true      ? _FiltreActus.medias
    : _FiltreActus.redaction;

class PageActualites extends ConsumerStatefulWidget {
  const PageActualites({super.key});
  @override
  ConsumerState<PageActualites> createState() => _PageActualitesState();
}

class _PageActualitesState extends ConsumerState<PageActualites> {
  _FiltreActus _filtre = _FiltreActus.tout;
  Set<String> _lus = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _lus = (p.getStringList('news_read_ids') ?? []).toSet());
    });
  }

  Future<void> _ouvrir(Map<String, dynamic> news) async {
    HapticFeedback.mediumImpact();
    final id = news['id'] as String? ?? '';
    if (id.isNotEmpty && !_lus.contains(id)) {
      setState(() => _lus = {..._lus, id});
      final p = await SharedPreferences.getInstance();
      await p.setStringList('news_read_ids', _lus.toList());
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewsDetailSheet(news: news),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(toutesActualitesProvider);
    final libelles = {
      _FiltreActus.tout:      tr(context, "Tout"),
      _FiltreActus.resumes:   tr(context, "Résumés de match"),
      _FiltreActus.medias:    tr(context, "Médias"),
      _FiltreActus.redaction: tr(context, "PronoWin"),
    };
    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: tr(context, "Retour"),
          onPressed: () => retourOuAller(context, repli: '/')),
        title: Text(tr(context, "Actualités")),
        centerTitle: true,
      ),
      body: etat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(context, "Actualités momentanément indisponibles."),
              textAlign: TextAlign.center, style: TextStyle(color: context.cl.textS)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(toutesActualitesProvider),
              child: Text(tr(context, "Réessayer"))),
          ]),
        )),
        data: (toutes) {
          // Une famille sans article n'a pas de filtre.
          final familles = {for (final n in toutes) _familleActu(n)};
          final visibles = _filtre == _FiltreActus.tout
              ? toutes
              : toutes.where((n) => _familleActu(n) == _filtre).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(toutesActualitesProvider);
              await ref.read(toutesActualitesProvider.future).catchError((_) => <Map<String, dynamic>>[]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (familles.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in _FiltreActus.values)
                        if (f == _FiltreActus.tout || familles.contains(f))
                          ChoiceChip(
                            key: Key('filtre-actus-${f.name}'),
                            label: Text(libelles[f]!),
                            selected: _filtre == f,
                            onSelected: (_) => setState(() => _filtre = f),
                          ),
                    ]),
                  ),
                if (visibles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(tr(context, "Aucune actualité pour l'instant."),
                      textAlign: TextAlign.center, style: TextStyle(color: context.cl.textS)),
                  ),
                for (final n in visibles)
                  _CompactNewsCard(
                    news: n,
                    isRead: _lus.contains(n['id'] as String? ?? ''),
                    onTap: () => _ouvrir(n),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
