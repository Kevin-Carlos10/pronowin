import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

// ── Modèles ───────────────────────────────────────────────────────────────────
class PronosticComment {
  final String  id;
  final String  userId;
  final String  content;
  final bool    isExpert;
  final String? parentId;
  final DateTime createdAt;
  final String  userPseudo;
  final String? userAvatar;
  final List<PronosticComment> replies;

  const PronosticComment({
    required this.id,
    required this.userId,
    required this.content,
    required this.isExpert,
    this.parentId,
    required this.createdAt,
    required this.userPseudo,
    this.userAvatar,
    this.replies = const [],
  });

  factory PronosticComment.fromJson(Map<String, dynamic> j) => PronosticComment(
    id:         j['id'] as String,
    userId:     j['userId'] as String? ?? '',
    content:    j['content'] as String,
    isExpert:   j['isExpert'] as bool? ?? false,
    parentId:   j['parentId'] as String?,
    createdAt:  DateTime.parse(j['createdAt'] as String),
    userPseudo: (j['user'] as Map<String, dynamic>)['pseudo'] as String,
    userAvatar: (j['user'] as Map<String, dynamic>)['avatarUrl'] as String?,
    replies:    (j['replies'] as List? ?? [])
        .map((r) => PronosticComment.fromJson(r as Map<String, dynamic>))
        .toList(),
  );
}

class PronosticVoteData {
  final String? userVote;
  final int     agree;
  final int     disagree;
  final int     total;

  const PronosticVoteData({
    this.userVote,
    required this.agree,
    required this.disagree,
    required this.total,
  });

  factory PronosticVoteData.fromJson(Map<String, dynamic> j) => PronosticVoteData(
    userVote: j['userVote'] as String?,
    agree:    (j['agree']    as num).toInt(),
    disagree: (j['disagree'] as num).toInt(),
    total:    (j['total']    as num).toInt(),
  );
}

class CommentsData {
  final List<PronosticComment> comments;
  final PronosticVoteData      vote;
  const CommentsData({required this.comments, required this.vote});

  factory CommentsData.fromJson(Map<String, dynamic> j) => CommentsData(
    comments: (j['comments'] as List)
        .map((c) => PronosticComment.fromJson(c as Map<String, dynamic>))
        .toList(),
    vote: PronosticVoteData.fromJson(j['vote'] as Map<String, dynamic>),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final commentsProvider = FutureProvider.autoDispose
    .family<CommentsData, String>((ref, pronosticId) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/comments/$pronosticId');
  return CommentsData.fromJson(r.data as Map<String, dynamic>);
});

// ── Widget principal ──────────────────────────────────────────────────────────
class CommentsSection extends ConsumerStatefulWidget {
  final String pronosticId;
  const CommentsSection({super.key, required this.pronosticId});

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  String? _replyingTo;       // commentId en cours de réponse
  String? _replyingToPseudo;
  bool    _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _vote(String type) async {
    HapticFeedback.selectionClick();
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/comments/${widget.pronosticId}/vote', data: {'type': type});
      ref.invalidate(commentsProvider(widget.pronosticId));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/comments/${widget.pronosticId}', data: {
        'content':   text,
        if (_replyingTo != null) 'parent_id': _replyingTo,
      });
      _ctrl.clear();
      _focus.unfocus();
      setState(() { _replyingTo = null; _replyingToPseudo = null; });
      ref.invalidate(commentsProvider(widget.pronosticId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String commentId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/comments/${widget.pronosticId}/comment/$commentId');
      ref.invalidate(commentsProvider(widget.pronosticId));
    } catch (_) {}
  }

  void _confirmDelete(String commentId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteCommentSheet(onConfirm: () async {
        await _delete(commentId);
        if (mounted) Navigator.pop(context);
      }),
    );
  }

  void _startReply(String commentId, String pseudo) {
    setState(() { _replyingTo = commentId; _replyingToPseudo = pseudo; });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.pronosticId));
    final commentsErr   = commentsAsync.error;
    final authState      = ref.watch(authProvider);
    final currentUserId  = authState is AuthAuthenticated ? authState.user.id : null;
    // 403 = connecté mais pas Premium. 401 = pas de compte du tout — cas
    // devenu courant depuis que le détail d'un match est ouvert aux invités.
    // Les confondre affichait une exception Dart brute à l'invité, et lui
    // laissait le champ de saisie alors que l'envoi allait échouer.
    final status = commentsErr is DioException
        ? commentsErr.response?.statusCode : null;
    final isPremiumRequired = commentsErr is DioException &&
        (status == 403 || commentsErr.response?.data?['code'] == 'PREMIUM_REQUIRED');
    final needsLogin = status == 401;
    final isGated    = isPremiumRequired || needsLogin;

    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── En-tête ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.forum_rounded, color: AppColors.info, size: 16)),
            const SizedBox(width: 10),
            Text('Avis de la communauté',
              style: TextStyle(color: context.cl.textP, fontSize: 13,
                  fontWeight: FontWeight.w700)),
            const Spacer(),
            commentsAsync.when(
              loading: () => const SizedBox.shrink(),
              error:   (_, _) => const SizedBox.shrink(),
              data: (d) => Text('${d.comments.length}',
                style: TextStyle(color: context.cl.textM, fontSize: 12)),
            ),
          ]),
        ),

        // ── Vote bar ───────────────────────────────────────────────────────
        commentsAsync.when(
          loading: () => const _VoteBarSkeleton(),
          error:   (_, _) => const SizedBox.shrink(),
          data: (d) => _VoteBar(
            vote:   d.vote,
            onAgree:    () => _vote('AGREE'),
            onDisagree: () => _vote('DISAGREE'),
          ).animate(delay: 80.ms).fadeIn(duration: 300.ms),
        ),

        const Divider(height: 1),

        // ── Liste commentaires ─────────────────────────────────────────────
        commentsAsync.when(
          loading: () => const _CommentsLoading(),
          error:   (e, _) => needsLogin
            ? _CommentsGuestLocked(
                onTap: () => context.push(
                  '/auth/email?from=${Uri.encodeComponent('/pronostics/${widget.pronosticId}')}'))
            : isPremiumRequired
              ? _CommentsPremiumLocked(onTap: () => goToPremium(context, ref))
              : _CommentsError(message: e.toString()),
          data: (d) => d.comments.isEmpty
            ? _EmptyComments()
            : Column(
                children: d.comments.asMap().entries.map((entry) =>
                  _CommentTile(
                    comment:       entry.value,
                    delay:         entry.key * 40,
                    currentUserId: currentUserId,
                    onReply:       _startReply,
                    onDelete:      _confirmDelete,
                  ),
                ).toList(),
              ),
        ),

        // ── Input — réservé aux membres Premium ──────────────────────────
        if (!isGated) ...[
          const Divider(height: 1),
          _CommentInput(
            controller:        _ctrl,
            focusNode:         _focus,
            replyingToPseudo:  _replyingToPseudo,
            sending:           _sending,
            onCancelReply:     () => setState(() {
              _replyingTo = null;
              _replyingToPseudo = null;
            }),
            onSend: _send,
          ),
        ],
      ]),
    );
  }
}

// ── Vote bar ──────────────────────────────────────────────────────────────────
class _VoteBar extends StatelessWidget {
  final PronosticVoteData vote;
  final VoidCallback onAgree, onDisagree;
  const _VoteBar({required this.vote, required this.onAgree, required this.onDisagree});

  @override
  Widget build(BuildContext context) {
    final total      = vote.total;
    final agreePct   = total > 0 ? vote.agree    / total : 0.5;
    final userAgreed = vote.userVote == 'AGREE';
    final userDis    = vote.userVote == 'DISAGREE';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ton avis sur ce pronostic ?',
          style: TextStyle(color: context.cl.textS, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          // Bouton D'accord
          Expanded(child: GestureDetector(
            onTap: onAgree,
            child: AnimatedContainer(
              duration: 180.ms,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: userAgreed
                    ? AppColors.success.withValues(alpha: 0.15)
                    : context.cl.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: userAgreed
                      ? AppColors.success
                      : context.cl.border,
                  width: userAgreed ? 1.5 : 0.5)),
              child: Column(children: [
                Text('👍', style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text('D\'accord', style: TextStyle(
                  color: userAgreed ? AppColors.success : context.cl.textM,
                  fontSize: 11, fontWeight: FontWeight.w700)),
                Text('${vote.agree}', style: TextStyle(
                  color: userAgreed ? AppColors.success : context.cl.textS,
                  fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ),
          )),
          const SizedBox(width: 10),
          // Bouton Pas convaincu
          Expanded(child: GestureDetector(
            onTap: onDisagree,
            child: AnimatedContainer(
              duration: 180.ms,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: userDis
                    ? AppColors.error.withValues(alpha: 0.12)
                    : context.cl.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: userDis ? AppColors.error : context.cl.border,
                  width: userDis ? 1.5 : 0.5)),
              child: Column(children: [
                Text('👎', style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text('Pas convaincu', style: TextStyle(
                  color: userDis ? AppColors.error : context.cl.textM,
                  fontSize: 11, fontWeight: FontWeight.w700)),
                Text('${vote.disagree}', style: TextStyle(
                  color: userDis ? AppColors.error : context.cl.textS,
                  fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ),
          )),
        ]),
        if (total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: agreePct),
              duration: 700.ms,
              curve: Curves.easeOutCubic,
              builder: (_, val, _) => Stack(children: [
                Container(height: 6,
                  color: AppColors.error.withValues(alpha: 0.5)),
                FractionallySizedBox(
                  widthFactor: val,
                  child: Container(height: 6,
                    color: AppColors.success.withValues(alpha: 0.85))),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text('$total avis · ${(agreePct * 100).round()}% d\'accord',
            style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ],
      ]),
    );
  }
}

// ── Tile commentaire ──────────────────────────────────────────────────────────
class _CommentTile extends StatelessWidget {
  final PronosticComment comment;
  final int              delay;
  final String?          currentUserId;
  final void Function(String id, String pseudo) onReply;
  final void Function(String id) onDelete;

  const _CommentTile({
    required this.comment,
    required this.delay,
    required this.currentUserId,
    required this.onReply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    _SingleComment(
      comment:  comment,
      canDelete: currentUserId != null && currentUserId == comment.userId,
      onReply:  () => onReply(comment.id, comment.userPseudo),
      onDelete: () => onDelete(comment.id),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn(duration: 250.ms),
    // Réponses
    ...comment.replies.map((r) => Padding(
      padding: const EdgeInsets.only(left: 32),
      child: _SingleComment(
        comment:  r,
        canDelete: currentUserId != null && currentUserId == r.userId,
        onReply:  () => onReply(comment.id, r.userPseudo),
        onDelete: () => onDelete(r.id),
        isReply:  true,
      ),
    )),
  ]);
}

class _SingleComment extends StatelessWidget {
  final PronosticComment comment;
  final bool              canDelete;
  final VoidCallback     onReply;
  final VoidCallback     onDelete;
  final bool             isReply;

  const _SingleComment({
    required this.comment,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('dd/MM · HH:mm').format(comment.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.cl.border, width: 0.4),
          left: isReply
              ? BorderSide(
                  color: comment.isExpert
                      ? AppColors.warning.withValues(alpha: 0.5)
                      : context.cl.border,
                  width: 2)
              : BorderSide.none,
        ),
        color: comment.isExpert
            ? AppColors.warning.withValues(alpha: 0.04)
            : Colors.transparent,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar + pseudo + temps
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: comment.isExpert
                  ? AppColors.warning.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle),
            child: Center(child: Text(
              comment.userPseudo.isNotEmpty
                  ? comment.userPseudo[0].toUpperCase()
                  : 'P',
              style: TextStyle(
                color: comment.isExpert ? AppColors.warning : AppColors.primary,
                fontSize: 12, fontWeight: FontWeight.w700)))),
          const SizedBox(width: 8),
          Expanded(child: Row(children: [
            Text(comment.userPseudo,
              style: TextStyle(
                color: comment.isExpert ? AppColors.warning : context.cl.textP,
                fontSize: 12, fontWeight: FontWeight.w700)),
            if (comment.isExpert) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
                child: const Text('Tipster ✓', style: TextStyle(
                  color: AppColors.warning, fontSize: 9,
                  fontWeight: FontWeight.w800))),
            ],
          ])),
          Text(timeStr, style: TextStyle(color: context.cl.textM, fontSize: 10)),
        ]),

        const SizedBox(height: 6),

        // Contenu
        Text(comment.content,
          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4)),

        const SizedBox(height: 6),

        // Actions
        Row(children: [
          GestureDetector(
            onTap: onReply,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.reply_rounded, size: 14, color: context.cl.textM),
              const SizedBox(width: 3),
              Text('Répondre', style: TextStyle(color: context.cl.textM, fontSize: 11)),
            ])),
          if (canDelete) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onDelete,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.error),
                const SizedBox(width: 3),
                Text('Supprimer', style: TextStyle(color: AppColors.error, fontSize: 11)),
              ])),
          ],
        ]),
      ]),
    );
  }
}

// ── Input commentaire ─────────────────────────────────────────────────────────
class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode            focusNode;
  final String?              replyingToPseudo;
  final bool                 sending;
  final VoidCallback         onCancelReply;
  final VoidCallback         onSend;

  const _CommentInput({
    required this.controller,
    required this.focusNode,
    this.replyingToPseudo,
    required this.sending,
    required this.onCancelReply,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Bandeau de réponse
      if (replyingToPseudo != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: AppColors.info.withValues(alpha: 0.06),
          child: Row(children: [
            Icon(Icons.reply_rounded, size: 14, color: AppColors.info),
            const SizedBox(width: 6),
            Text('Répondre à $replyingToPseudo',
              style: const TextStyle(color: AppColors.info, fontSize: 12)),
            const Spacer(),
            GestureDetector(
              onTap: onCancelReply,
              child: Icon(Icons.close_rounded, size: 16, color: context.cl.textM)),
          ])),

      // Champ de texte
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: controller,
            focusNode:  focusNode,
            maxLines:   3,
            minLines:   1,
            maxLength:  500,
            style: TextStyle(color: context.cl.textP, fontSize: 13),
            decoration: InputDecoration(
              hintText:       'Partage ton avis sur ce pronostic…',
              hintStyle:      TextStyle(color: context.cl.textM, fontSize: 13),
              counterText:    '',
              filled:         true,
              fillColor:      context.cl.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border:         OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:   BorderSide(color: context.cl.border, width: 0.5)),
              focusedBorder:  OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:   const BorderSide(color: AppColors.info, width: 1.2)),
              enabledBorder:  OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:   BorderSide(color: context.cl.border, width: 0.5)),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: AnimatedContainer(
              duration: 180.ms,
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.info,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                  color: AppColors.info.withValues(alpha: 0.3),
                  blurRadius: 8, offset: const Offset(0, 3))]),
              child: sending
                  ? const Center(child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18)),
          ),
        ]),
      ),
    ],
  );
}

// ── États vides / erreur / loading ────────────────────────────────────────────
class _EmptyComments extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(children: [
      Text('💬', style: const TextStyle(fontSize: 32)),
      const SizedBox(height: 8),
      Text('Soyez le premier à commenter !',
        style: TextStyle(color: context.cl.textS, fontSize: 13)),
    ]),
  );
}

class _CommentsLoading extends StatelessWidget {
  const _CommentsLoading();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(children: List.generate(3, (_) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      height: 50,
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(8)),
    ).animate(onPlay: (c) => c.repeat())
     .shimmer(duration: 1400.ms, color: context.cl.borderSoft))),
  );
}

class _CommentsError extends StatelessWidget {
  final String message;
  const _CommentsError({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text('Commentaires indisponibles.',
      style: TextStyle(color: context.cl.textM, fontSize: 12)),
  );
}

/// Même traitement que le verrou de l'analyse statistique (aperçu flouté + CTA doré) :
/// les deux cartes verrouillées se suivent dans l'onglet Détails, elles ne
/// peuvent pas avoir deux styles différents.
class _CommentsPremiumLocked extends StatefulWidget {
  final VoidCallback onTap;
  const _CommentsPremiumLocked({required this.onTap});

  @override
  State<_CommentsPremiumLocked> createState() => _CommentsPremiumLockedState();
}

class _CommentsPremiumLockedState extends State<_CommentsPremiumLocked>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFDAA520);
  static const _goldLight = Color(0xFFF4C430);

  late final AnimationController _pressCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 85),
    reverseDuration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.97).animate(
    CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const Opacity(opacity: 0.55, child: _CommentsPreviewMock()),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      context.cl.surfaceD.withValues(alpha: 0.55),
                      context.cl.surfaceD.withValues(alpha: 0.93),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_goldLight, _gold]),
                  ),
                  child: const Icon(Icons.forum_rounded, color: Colors.black, size: 19),
                ),
                const SizedBox(height: 10),
                Text('Rejoignez la discussion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cl.textP,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Lisez et partagez les analyses de la communauté',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_goldLight, _gold]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(
                      color: _gold.withValues(alpha: 0.35),
                      blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  // Même pastille dorée que le verrou de l'analyse statistique (signal
                  // « action Premium »), mais libellé distinct : les deux
                  // cartes se suivent, deux CTA identiques feraient doublon.
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_open_rounded, color: Colors.black, size: 15),
                    SizedBox(width: 6),
                    Text('Rejoindre la discussion',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                  ]),
                ).animate(onPlay: (c) => c.repeat())
                 .shimmer(duration: 2200.ms, delay: 700.ms, color: Colors.white70),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Squelette de fil de discussion, flouté derrière le CTA — suggère qu'il y a
/// de vrais échanges à lire, sans inventer de faux commentaires.
class _CommentsPreviewMock extends StatelessWidget {
  const _CommentsPreviewMock();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      _row(context, 0.75),
      const SizedBox(height: 14),
      _row(context, 0.55),
      const SizedBox(height: 14),
      _row(context, 0.65),
    ]),
  );

  Widget _row(BuildContext context, double widthFactor) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: context.cl.borderSoft, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 8, width: 70,
            decoration: BoxDecoration(
              color: context.cl.borderSoft,
              borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          FractionallySizedBox(
            widthFactor: widthFactor,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                color: context.cl.borderSoft,
                borderRadius: BorderRadius.circular(4))),
          ),
        ]),
      ),
    ],
  );
}

// ── Bottom sheet : confirmation suppression commentaire ────────────────────────
class _DeleteCommentSheet extends StatefulWidget {
  final Future<void> Function() onConfirm;
  const _DeleteCommentSheet({required this.onConfirm});

  @override
  State<_DeleteCommentSheet> createState() => _DeleteCommentSheetState();
}

class _DeleteCommentSheetState extends State<_DeleteCommentSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cl.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          shape: BoxShape.circle),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 32)),
      const SizedBox(height: 16),
      Text('Supprimer ce commentaire ?', style: TextStyle(
        color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Cette action est définitive.', style: TextStyle(
        color: context.cl.textS, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cl.textP,
            side: BorderSide(color: context.cl.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Annuler'),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: _loading ? null : () async {
            setState(() => _loading = true);
            await widget.onConfirm();
            if (mounted) setState(() => _loading = false);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    ]),
  );
}

class _VoteBarSkeleton extends StatelessWidget {
  const _VoteBarSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    height: 70,
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(10)),
  ).animate(onPlay: (c) => c.repeat())
   .shimmer(duration: 1400.ms, color: context.cl.borderSoft);
}

/// Invite à créer un compte — état distinct du verrou Premium.
///
/// Un invité peut désormais atteindre le détail d'un match : lui montrer
/// « réservé aux Premium » serait faux, il lui manque d'abord un compte.
class _CommentsGuestLocked extends StatelessWidget {
  final VoidCallback onTap;
  const _CommentsGuestLocked({required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
    child: Column(children: [
      Icon(Icons.forum_outlined, color: context.cl.textM, size: 30),
      const SizedBox(height: 12),
      Text('Rejoins la discussion',
        style: TextStyle(color: context.cl.textP, fontSize: 15,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        'Crée un compte gratuit pour lire les commentaires et échanger avec '
        'les autres parieurs.',
        style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity, height: 46,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))),
          child: const Text('Créer un compte gratuit',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}
