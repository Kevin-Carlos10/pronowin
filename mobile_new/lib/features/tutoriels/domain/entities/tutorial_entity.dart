// ─── Enums ────────────────────────────────────────────────────────────────────
enum TutorialLevel {
  beginner,
  intermediate,
  advanced;

  String get label => switch (this) {
    TutorialLevel.beginner     => 'Débutant',
    TutorialLevel.intermediate => 'Intermédiaire',
    TutorialLevel.advanced     => 'Avancé',
  };

  static TutorialLevel fromString(String? s) => switch (s) {
    'intermediate' => TutorialLevel.intermediate,
    'advanced'     => TutorialLevel.advanced,
    _              => TutorialLevel.beginner,
  };
}

enum TutorialCategory {
  valuebet,
  bankroll,
  martingale,
  trading,
  psychology,
  statistics,
  strategie,
  analyse,
  psychologie;

  String get label => switch (this) {
    TutorialCategory.valuebet    => 'Value Bet',
    TutorialCategory.bankroll    => 'Bankroll',
    TutorialCategory.martingale  => 'Martingale',
    TutorialCategory.trading     => 'Trading',
    TutorialCategory.psychology  => 'Psychologie',
    TutorialCategory.psychologie => 'Psychologie',
    TutorialCategory.statistics  => 'Statistiques',
    TutorialCategory.strategie   => 'Stratégie',
    TutorialCategory.analyse     => 'Analyse',
  };

  String get emoji => switch (this) {
    TutorialCategory.valuebet    => '🎯',
    TutorialCategory.bankroll    => '💰',
    TutorialCategory.martingale  => '🔄',
    TutorialCategory.trading     => '⚡',
    TutorialCategory.psychology  => '🧠',
    TutorialCategory.psychologie => '🧠',
    TutorialCategory.statistics  => '📊',
    TutorialCategory.strategie   => '♟️',
    TutorialCategory.analyse     => '📊',
  };

  static TutorialCategory fromString(String? s) => switch (s?.toLowerCase()) {
    'bankroll'    => TutorialCategory.bankroll,
    'martingale'  => TutorialCategory.martingale,
    'trading'     => TutorialCategory.trading,
    'psychology'  => TutorialCategory.psychology,
    'psychologie' => TutorialCategory.psychologie,
    'statistics'  => TutorialCategory.statistics,
    'strategie'   => TutorialCategory.strategie,
    'analyse'     => TutorialCategory.analyse,
    _             => TutorialCategory.valuebet,
  };
}

// ─── Entity ───────────────────────────────────────────────────────────────────
class TutorialEntity {
  final String           id;
  final String           title;
  final String           description;
  final TutorialLevel    level;
  final TutorialCategory category;
  final String?          thumbnailUrl;
  final String?          videoUrl;
  final String?          articleContent;  // contenu article texte
  final String?          authorName;
  final String?          authorAvatar;
  final int              durationSeconds;
  final int              viewCount;
  final double           rating;
  final bool             isPremium;
  final bool             hasVideo;
  final bool             isCompleted;
  final DateTime?        publishedAt;

  const TutorialEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.level,
    required this.category,
    this.thumbnailUrl,
    this.videoUrl,
    this.articleContent,
    this.authorName,
    this.authorAvatar,
    this.durationSeconds = 0,
    this.viewCount       = 0,
    this.rating          = 0.0,
    this.isPremium       = false,
    this.hasVideo        = false,
    this.isCompleted     = false,
    this.publishedAt,
  });

  // ─── Getters pratiques ────────────────────────────────────────────────────
  String get levelLabel    => level.label;
  String get categoryLabel => category.label;
  String get categoryEmoji => category.emoji;

  String get durationText {
    final m = durationSeconds ~/ 60;
    if (m == 0) return '—';
    return m < 60 ? '${m}min' : '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  }

  // Alias pour compatibilité avec du code qui utilise durationLabel
  String get durationLabel => durationText;

  // ─── fromJson ─────────────────────────────────────────────────────────────
  factory TutorialEntity.fromJson(Map<String, dynamic> j) => TutorialEntity(
    id:              j['id']          as String,
    title:           j['title']       as String,
    description:     j['description'] as String? ?? '',
    level:           TutorialLevel.fromString(j['level'] as String?),
    category:        TutorialCategory.fromString(j['category'] as String?),
    thumbnailUrl:    j['thumbnail_url']  as String?,
    videoUrl:        j['video_url']      as String?,
    articleContent:  j['article_content'] as String?,
    authorName:      j['author_name']    as String?,
    authorAvatar:    j['author_avatar']  as String?,
    durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
    viewCount:       (j['view_count']       as num?)?.toInt() ?? 0,
    rating:          (j['rating']           as num?)?.toDouble() ?? 0.0,
    isPremium:       j['is_premium']  as bool? ?? false,
    hasVideo:        j['has_video']   as bool? ?? false,
    isCompleted:     j['is_completed'] as bool? ?? false,
    publishedAt:     j['published_at'] != null
      ? DateTime.tryParse(j['published_at'] as String) : null,
  );

  // ─── toJson ───────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id':               id,
    'title':            title,
    'description':      description,
    'level':            level.name,
    'category':         category.name,
    'thumbnail_url':    thumbnailUrl,
    'video_url':        videoUrl,
    'article_content':  articleContent,
    'author_name':      authorName,
    'author_avatar':    authorAvatar,
    'duration_seconds': durationSeconds,
    'view_count':       viewCount,
    'rating':           rating,
    'is_premium':       isPremium,
    'has_video':        hasVideo,
    'is_completed':     isCompleted,
    'published_at':     publishedAt?.toIso8601String(),
  };

  TutorialEntity copyWith({
    String? id, String? title, String? description,
    TutorialLevel? level, TutorialCategory? category,
    String? thumbnailUrl, String? videoUrl, String? articleContent,
    String? authorName, String? authorAvatar,
    int? durationSeconds, int? viewCount, double? rating,
    bool? isPremium, bool? hasVideo, bool? isCompleted,
    DateTime? publishedAt,
  }) => TutorialEntity(
    id:              id              ?? this.id,
    title:           title           ?? this.title,
    description:     description     ?? this.description,
    level:           level           ?? this.level,
    category:        category        ?? this.category,
    thumbnailUrl:    thumbnailUrl    ?? this.thumbnailUrl,
    videoUrl:        videoUrl        ?? this.videoUrl,
    articleContent:  articleContent  ?? this.articleContent,
    authorName:      authorName      ?? this.authorName,
    authorAvatar:    authorAvatar    ?? this.authorAvatar,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    viewCount:       viewCount       ?? this.viewCount,
    rating:          rating          ?? this.rating,
    isPremium:       isPremium       ?? this.isPremium,
    hasVideo:        hasVideo        ?? this.hasVideo,
    isCompleted:     isCompleted     ?? this.isCompleted,
    publishedAt:     publishedAt     ?? this.publishedAt,
  );
}

// ─── Progress Entity ──────────────────────────────────────────────────────────
class TutorialProgressEntity {
  final String    tutorialId;
  final bool      isCompleted;
  final DateTime? completedAt;
  final int       progressPercent;

  const TutorialProgressEntity({
    required this.tutorialId,
    this.isCompleted     = false,
    this.completedAt,
    this.progressPercent = 0,
  });

  factory TutorialProgressEntity.fromJson(Map<String, dynamic> j) =>
    TutorialProgressEntity(
      tutorialId:      j['tutorial_id']     as String,
      isCompleted:     j['is_completed']    as bool? ?? false,
      progressPercent: (j['progress_percent'] as num?)?.toInt() ?? 0,
      completedAt:     j['completed_at'] != null
        ? DateTime.tryParse(j['completed_at'] as String) : null,
    );
}
