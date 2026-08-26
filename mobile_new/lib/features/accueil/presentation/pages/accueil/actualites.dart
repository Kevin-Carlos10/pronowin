// Section actualités — extrait de accueil_page.dart.
//
// `part` et non un fichier autonome : ces classes sont privées à la
// bibliothèque (préfixe `_`) et doivent le rester. Un import classique
// aurait imposé de les rendre publiques, donc visibles de partout.
part of '../accueil_page.dart';

class _NewsSection extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _NewsSection({required this.items});
  @override
  State<_NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<_NewsSection> {
  Set<String> _readIds = {};
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _loadRead();
  }

  Future<void> _loadRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList('news_read_ids') ?? [];
    if (mounted) setState(() => _readIds = list.toSet());
  }

  Future<void> _markRead(String id) async {
    if (_readIds.contains(id)) return;
    final prefs = await SharedPreferences.getInstance();
    _readIds.add(id);
    await prefs.setStringList('news_read_ids', _readIds.toList());
    if (mounted) setState(() {});
  }

  void _openArticle(BuildContext context, Map<String, dynamic> news) {
    HapticFeedback.mediumImpact();
    _markRead(news['id'] as String? ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewsDetailSheet(news: news),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pinned en premier, puis tri par date
    final sorted = [...widget.items]..sort((a, b) {
      final aPin = (a['is_pinned'] as bool? ?? false) ? 0 : 1;
      final bPin = (b['is_pinned'] as bool? ?? false) ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);
      final da = DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    final unreadCount = sorted.where((n) => !_readIds.contains(n['id'] as String? ?? '')).length;
    final visible = _showAll ? sorted : sorted.take(4).toList();

    // La carte en vedette occupe un tiers d'écran : un titre d'un seul mot
    // (« Paul Pogba ») y fait négligé. On promeut le premier titre qui a de
    // la matière, sans changer l'ordre du reste.
    if (visible.length > 1) {
      final i = visible.indexWhere(
          (n) => ((n['title'] as String?) ?? '').trim().length >= 25);
      if (i > 0) visible.insert(0, visible.removeAt(i));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — même composant que les autres sections de l'écran.
        _SectionHeader(
          title: 'Actualités football',
          leading: Icon(Icons.newspaper_rounded,
              color: context.cl.textM, size: 15),
          showBadge: unreadCount > 0 ? unreadCount : null,
          badgeColor: AppColors.primary,
          moreLabel: _showAll ? 'Réduire' : 'Voir tout',
          onMore: sorted.length > 4
              ? () => setState(() => _showAll = !_showAll)
              : null,
        ),
        const SizedBox(height: 12),

        // Featured card (premier article)
        if (visible.isNotEmpty)
          _FeaturedNewsCard(
            news: visible.first,
            isRead: _readIds.contains(visible.first['id'] as String? ?? ''),
            onTap: () => _openArticle(context, visible.first),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0,
              curve: Curves.easeOutCubic),

        // Cards compactes (articles suivants)
        ...visible.skip(1).toList().asMap().entries.map((e) {
          final i    = e.key;
          final news = e.value;
          return _CompactNewsCard(
            news: news,
            isRead: _readIds.contains(news['id'] as String? ?? ''),
            onTap: () => _openArticle(context, news),
          )
          .animate(delay: Duration(milliseconds: 80 + i * 60))
          .fadeIn(duration: 300.ms)
          .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
        }),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// HELPERS COMMUNS NEWS
// ──────────────────────────────────────────────────────────────────────────────
Color _newsAccent(String? cat) {
  if (cat == null) return AppColors.primary;
  if (cat.contains('Monde'))      return const Color(0xFF10B981);
  if (cat.contains('Champions'))  return const Color(0xFFFFD700);
  if (cat.contains('Premier'))    return const Color(0xFF6366F1);
  if (cat.contains('Serie'))      return const Color(0xFF3B82F6);
  if (cat.contains('Liga'))       return AppColors.error;
  if (cat.contains('Ligue 1'))    return const Color(0xFF8B5CF6);
  return AppColors.primary;
}

// ──────────────────────────────────────────────────────────────────────────────
Map<String, String> _imgHeaders(String url) {
  if (url.contains('bfmtv.com') || url.contains('images.bfmtv')) {
    return {'Referer': 'https://rmcsport.bfmtv.com/'};
  }
  if (url.contains('bbci.co.uk') || url.contains('ichef.bbc')) {
    return {'Referer': 'https://www.bbc.com/'};
  }
  return {};
}

// FEATURED CARD — grande carte avec image pleine largeur
// ──────────────────────────────────────────────────────────────────────────────
class _FeaturedNewsCard extends StatelessWidget {
  final Map<String, dynamic> news;
  final bool isRead;
  final VoidCallback onTap;
  const _FeaturedNewsCard({required this.news, required this.isRead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat    = news['categorie'] as String?;
    final accent = _newsAccent(cat);
    final imgUrl = news['image_url'] as String?;
    final isPinned = news['is_pinned'] as bool? ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 200,
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isRead ? context.cl.border : accent.withValues(alpha: 0.4),
            width: isRead ? 0.5 : 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            // Image fond
            if (imgUrl != null && imgUrl.isNotEmpty)
              Positioned.fill(
                child: ImageDistante(
                  url:     imgUrl,
                  entetes: _imgHeaders(imgUrl),
                  repli:   Container(color: context.cl.surfaceD)),
              )
            else
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.15), context.cl.surfaceD],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
              )),

            // Dégradé bas
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                )),
            )),

            // Barre accent gauche
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent)),

            // Contenu
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top : catégorie + badges
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(cat ?? '',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                    if (isPinned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.push_pin_rounded, color: Colors.white, size: 9),
                          SizedBox(width: 3),
                          Text('À la une',
                            style: TextStyle(color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],
                    const Spacer(),
                    if (!isRead)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      ),
                  ]),
                  const Spacer(),
                  // Titre
                  Text(news['titre'] as String? ?? '',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800, height: 1.3),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  // Date + emoji
                  Row(children: [
                    Text(news['emoji'] as String? ?? '',
                      style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Icon(Icons.schedule_rounded, size: 11, color: Colors.white70),
                    const SizedBox(width: 3),
                    Text(news['date'] as String? ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// COMPACT CARD — ligne horizontale
// ──────────────────────────────────────────────────────────────────────────────
class _CompactNewsCard extends StatelessWidget {
  final Map<String, dynamic> news;
  final bool isRead;
  final VoidCallback onTap;
  const _CompactNewsCard({required this.news, required this.isRead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat    = news['categorie'] as String?;
    final accent = _newsAccent(cat);
    final imgUrl = news['image_url'] as String?;
    final hasImg = imgUrl != null && imgUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? context.cl.border : accent.withValues(alpha: 0.35),
            width: isRead ? 0.5 : 1,
          ),
        ),
        child: Row(children: [
          // Miniature image ou emoji
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hasImg
                ? ImageDistante(
                    url:     imgUrl,
                    largeur: 60, hauteur: 60,
                    entetes: _imgHeaders(imgUrl),
                    repli:   _NewsEmojiFallback(
                      emoji: news['emoji'] as String? ?? '📰', accent: accent))
                : _NewsEmojiFallback(emoji: news['emoji'] as String? ?? '📰', accent: accent),
          ),
          const SizedBox(width: 12),
          // Texte
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Catégorie
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(cat ?? '',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 5),
              // Titre
              Text(news['titre'] as String? ?? '',
                style: TextStyle(
                  color: isRead ? context.cl.textS : context.cl.textP,
                  fontSize: 12,
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                  height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              // Date
              Row(children: [
                Icon(Icons.schedule_rounded, size: 10, color: context.cl.textM),
                const SizedBox(width: 3),
                Text(news['date'] as String? ?? '',
                  style: TextStyle(color: context.cl.textM, fontSize: 10)),
              ]),
            ],
          )),
          const SizedBox(width: 8),
          // Point non-lu
          if (!isRead)
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}

class _NewsEmojiFallback extends StatelessWidget {
  final String emoji;
  final Color accent;
  const _NewsEmojiFallback({required this.emoji, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
    width: 60, height: 60,
    color: accent.withValues(alpha: 0.10),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// NEWS DETAIL BOTTOM SHEET
// ──────────────────────────────────────────────────────────────────────────────
class _NewsDetailSheet extends StatelessWidget {
  final Map<String, dynamic> news;
  const _NewsDetailSheet({required this.news});

  @override
  Widget build(BuildContext context) {
    final cat       = news['categorie'] as String?;
    final accent    = _newsAccent(cat);
    final imgUrl    = news['image_url'] as String?;
    final resume    = news['resume'] as String? ?? '';
    final sourceUrl = news['source_url'] as String?;
    final hasSource = sourceUrl != null && sourceUrl.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.zero,
          children: [
            // Drag handle
            Center(child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: context.cl.border, borderRadius: BorderRadius.circular(2)),
            )),

            // Image header
            if (imgUrl != null && imgUrl.isNotEmpty)
              Stack(children: [
                SizedBox(
                  height: 200, width: double.infinity,
                  child: ImageDistante(
                    url:     imgUrl,
                    entetes: _imgHeaders(imgUrl),
                    repli:   const SizedBox.shrink())),
                Positioned.fill(child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter)),
                )),
                // Barre accent bas de l'image
                Positioned(left: 0, right: 0, bottom: 0,
                  child: Container(height: 3, color: accent)),
              ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Catégorie + date
                  Row(children: [
                    Text(news['emoji'] as String? ?? '', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.3))),
                      child: Text(cat ?? '',
                        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700))),
                    const Spacer(),
                    Row(children: [
                      Icon(Icons.schedule_rounded, size: 11, color: context.cl.textM),
                      const SizedBox(width: 3),
                      Text(news['date'] as String? ?? '',
                        style: TextStyle(color: context.cl.textM, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 14),

                  // Titre
                  Text(news['titre'] as String? ?? '',
                    style: TextStyle(
                      color: context.cl.textP, fontSize: 20,
                      fontWeight: FontWeight.w800, height: 1.3)),

                  if (resume.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(width: double.infinity, height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accent, accent.withValues(alpha: 0)]))),
                    const SizedBox(height: 14),
                    Text(resume,
                      style: TextStyle(
                        color: context.cl.textM, fontSize: 14, height: 1.65)),
                  ],

                  const SizedBox(height: 24),

                  // Bouton "Lire l'article complet" si source_url
                  if (hasSource) ...[
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () {
                          context.push('/navigateur', extra: {
                            'url':   sourceUrl,
                            'title': news['titre'] as String? ?? '',
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryLight]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 12, offset: const Offset(0, 4))]),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_new_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text('Lire l\'article complet',
                                style: TextStyle(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Bouton fermer
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: context.cl.surfaceD,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                      child: Text('Fermer',
                        style: TextStyle(
                          color: context.cl.textM, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════'
// COMPOSANTS UTILITAIRES
// ══════════════════════════════════════════════════════════════════════════════'
