import '../../domain/entities/tutorial_entity.dart';

class TutorialModel extends TutorialEntity {
  const TutorialModel({
    super.lessonContent,
    super.titleEn,
    super.descriptionEn,
    super.articleContentEn,
    required super.id,
    required super.title,
    required super.description,
    required super.level,
    required super.category,
    required super.thumbnailUrl,
    super.videoUrl,
    super.articleContent,
    required super.durationSeconds,
    required super.isPremium,
    required super.hasVideo,
    required super.viewCount,
    required super.rating,
    required super.isCompleted,
    required super.authorName,
    super.authorAvatar,
    required super.publishedAt,
  });

  factory TutorialModel.fromJson(Map<String, dynamic> j) => TutorialModel(
    lessonContent: Map<String, dynamic>.from(j['lesson_content'] as Map? ?? {}),
    titleEn: j['title_en'] as String?,
    descriptionEn: j['description_en'] as String?,
    articleContentEn: j['article_content_en'] as String?,
    id: j['id'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    level: _parseLevel(j['level'] as String?),
    category: (j['category'] as String?)?.trim().isNotEmpty == true
        ? (j['category'] as String).trim()
        : 'valuebet',
    thumbnailUrl: j['thumbnail_url'] as String? ?? '',
    videoUrl: j['video_url'] as String?,
    articleContent: j['article_content'] as String?,
    durationSeconds: j['duration_seconds'] as int? ?? 0,
    isPremium: j['is_premium'] as bool? ?? false,
    hasVideo: j['has_video'] as bool? ?? false,
    viewCount: j['view_count'] as int? ?? 0,
    rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
    isCompleted: j['is_completed'] as bool? ?? false,
    authorName: j['author_name'] as String? ?? 'Expert PronoWin',
    authorAvatar: j['author_avatar'] as String?,
    publishedAt: DateTime.parse(
      j['published_at'] as String? ?? DateTime.now().toIso8601String(),
    ).toLocal(),
  );

  static TutorialLevel _parseLevel(String? s) => switch (s) {
    'intermediate' => TutorialLevel.intermediate,
    'advanced' => TutorialLevel.advanced,
    _ => TutorialLevel.beginner,
  };
}
