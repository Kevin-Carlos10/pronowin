import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons.dart';
import '../providers/notification_service.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Rafraîchir à chaque ouverture de la page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationNotifierProvider.notifier).fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifAsync = ref.watch(notificationNotifierProvider);
    final unread     = ref.watch(unreadCountProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
            )
          : null,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [BoxShadow(color: Color(0x59E8541A),
                blurRadius: 8, offset: Offset(0, 3))]),
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.notifications_rounded, color: Colors.white, size: 17),
              if (unread > 0) Positioned(
                top: 4, right: 4,
                child: Container(width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle))),
            ])),
          const SizedBox(width: 10),
          Text('Notifications',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
              color: context.cl.textP)),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Container(
                key: ValueKey(unread),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x66EF4444),
                    blurRadius: 6, offset: Offset(0, 2))]),
                child: Text('$unread', style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
            ),
          ],
        ]),
        actions: [
          if (unread > 0)
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(notificationNotifierProvider.notifier).markAllRead();
              },
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text('Tout lire', style: TextStyle(fontSize: 13)),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(52),
          child: _FilterBar(),
        ),
      ),
      body: notifAsync.when(
        loading: () => const _NotifShimmer(),
        error: (_, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 44),
            const SizedBox(height: 12),
            Text('Impossible de charger les notifications',
              style: TextStyle(color: context.cl.textS, fontSize: 13),
              textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => ref.read(notificationNotifierProvider.notifier).fetch(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ]).animate().fadeIn(duration: 350.ms).scale(
              begin: const Offset(0.92, 0.92), end: const Offset(1, 1),
              duration: 350.ms, curve: Curves.easeOutBack),
        ),
        data: (_) => const _NotifBody(),
      ),
    );
  }
}

// ─── Barre de filtres ─────────────────────────────────────────────────────────
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(notifTypeFilterProvider);

    final filters = <NotificationType?, String>{
      null:                      'Tous',
      NotificationType.match:    'Match',
      NotificationType.promo:    'Promo',
      NotificationType.system:   'Système',
      NotificationType.payment:  'Paiement',
      NotificationType.referral: 'Parrainage',
    };

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final type  = filters.keys.elementAt(i);
          final label = filters.values.elementAt(i);
          final sel   = active == type;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(notifTypeFilterProvider.notifier).state = type;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : context.cl.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? AppColors.primary : context.cl.border,
                  width: sel ? 0 : 0.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (type != null) ...[
                  Icon(_typeIcon(type), size: 13,
                    color: sel ? Colors.white : _typeColor(type)),
                  const SizedBox(width: 5),
                ],
                Text(label,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : context.cl.textS)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Color _typeColor(NotificationType t) => switch (t) {
    NotificationType.match    => AppColors.success,
    NotificationType.promo    => AppColors.primaryLight,
    NotificationType.system   => AppColors.info,
    NotificationType.payment  => AppColors.warning,
    NotificationType.referral => const Color(0xFFA78BFA),
  };

  IconData _typeIcon(NotificationType t) => switch (t) {
    NotificationType.match    => Icons.sports_soccer_rounded,
    NotificationType.promo    => Icons.local_offer_rounded,
    NotificationType.system   => Icons.notifications_rounded,
    NotificationType.payment  => Icons.account_balance_wallet_rounded,
    NotificationType.referral => Icons.people_rounded,
  };
}

// ─── Corps principal (groupé par date) ───────────────────────────────────────
class _NotifBody extends ConsumerWidget {
  const _NotifBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(filteredNotifProvider);
    final filter = ref.watch(notifTypeFilterProvider);

    if (notifs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 72, height: 72,
            decoration: BoxDecoration(
              color: context.cl.surface, shape: BoxShape.circle,
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Icon(Icons.notifications_off_outlined,
              color: context.cl.textM, size: 36)),
          const SizedBox(height: 16),
          Text(filter == null ? 'Aucune notification' : 'Aucune notification ici',
            style: TextStyle(color: context.cl.textP,
              fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(filter == null ? 'Vous êtes à jour !' : 'Essayez un autre filtre',
            style: TextStyle(color: context.cl.textS, fontSize: 13)),
        ]).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9)),
      );
    }

    // Grouper par section de date
    final groups = _groupByDate(notifs);
    final sectionKeys = groups.keys.toList();

    // Construire la liste plate avec en-têtes
    final items = <_ListItem>[];
    for (final section in sectionKeys) {
      items.add(_ListItem.header(section));
      for (final n in groups[section]!) {
        items.add(_ListItem.notif(n));
      }
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: context.cl.surface,
      onRefresh: () => ref.read(notificationNotifierProvider.notifier).fetch(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item.isHeader) {
            return _DateHeader(label: item.label!)
              .animate(delay: Duration(milliseconds: i * 30))
              .fadeIn(duration: 200.ms);
          }
          return _SwipeTile(notif: item.notif!, index: i);
        },
      ),
    );
  }

  Map<String, List<AppNotification>> _groupByDate(List<AppNotification> list) {
    final now     = DateTime.now();
    final todayStr = _dayKey(now);
    final yestStr  = _dayKey(now.subtract(const Duration(days: 1)));

    final result = <String, List<AppNotification>>{};
    for (final n in list) {
      final key = _dayKey(n.createdAt);
      final String label;
      if (key == todayStr)                             { label = "Aujourd'hui"; }
      else if (key == yestStr)                         { label = 'Hier'; }
      else if (now.difference(n.createdAt).inDays < 7) { label = 'Cette semaine'; }
      else                                             { label = 'Plus ancien'; }
      result.putIfAbsent(label, () => []).add(n);
    }
    return result;
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

class _ListItem {
  final bool             isHeader;
  final String?          label;
  final AppNotification? notif;
  const _ListItem._({required this.isHeader, this.label, this.notif});
  factory _ListItem.header(String l)         => _ListItem._(isHeader: true,  label: l);
  factory _ListItem.notif(AppNotification n) => _ListItem._(isHeader: false, notif: n);
}

// ─── En-tête de date ──────────────────────────────────────────────────────────
class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(label, style: TextStyle(
      color: context.cl.textM, fontSize: 11,
      fontWeight: FontWeight.w700, letterSpacing: 0.6)),
  );
}

// ─── Tile avec swipe pour marquer lu ─────────────────────────────────────────
class _SwipeTile extends ConsumerWidget {
  final AppNotification notif;
  final int             index;
  const _SwipeTile({required this.notif, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(notif.id),
      direction: notif.isRead
          ? DismissDirection.none
          : DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: AppColors.primary.withValues(alpha: 0.1),
        child: Row(children: [
          Icon(Icons.mark_email_read_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Text('Marquer lu', style: TextStyle(
            color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.lightImpact();
        await ref.read(notificationNotifierProvider.notifier).markRead(notif.id);
        return false; // ne pas supprimer l'item, juste marquer comme lu
      },
      child: Column(children: [
        _NotifTile(notif: notif, onTap: () {
          HapticFeedback.lightImpact();
          ref.read(notificationNotifierProvider.notifier).markRead(notif.id);
          // ✅ Deep link : naviguer vers la destination si disponible
          final link = notif.deepLink;
          if (link != null && link.isNotEmpty) {
            context.go(link);
          }
        }),
        Divider(color: context.cl.border, height: 1, indent: 68, endIndent: 16),
      ]),
    )
    .animate(delay: Duration(milliseconds: index * 30))
    .fadeIn(duration: 250.ms)
    .slideX(begin: 0.05, end: 0);
  }
}

// ─── Shimmer chargement ───────────────────────────────────────────────────────
class _NotifShimmer extends StatelessWidget {
  const _NotifShimmer();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
    itemCount: 6,
    separatorBuilder: (_, _) => Divider(
      color: context.cl.border, height: 1, indent: 68, endIndent: 16),
    itemBuilder: (_, _) => const NotifTileSkeleton(),
  );
}

// ─── Tile notification ────────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback    onTap;
  const _NotifTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: notif.isRead
            ? Colors.transparent
            : AppColors.primary.withValues(alpha: 0.05),
        border: notif.isRead ? null : Border(
          left: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.6), width: 3))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _typeColor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(_typeIcon, color: _typeColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(notif.title, style: TextStyle(
              color: context.cl.textP, fontSize: 13,
              fontWeight: notif.isRead ? FontWeight.w400 : FontWeight.w700,
            ))),
            Text(_formatDate(notif.createdAt),
              style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(notif.body,
            style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        if (!notif.isRead) ...[
          const SizedBox(width: 8),
          _UnreadDot(),
        ],
      ]),
    ),
  );

  Color get _typeColor => switch (notif.type) {
    NotificationType.match    => AppColors.success,
    NotificationType.promo    => AppColors.primaryLight,
    NotificationType.system   => AppColors.info,
    NotificationType.payment  => AppColors.warning,
    NotificationType.referral => const Color(0xFFA78BFA),
  };

  IconData get _typeIcon => switch (notif.type) {
    NotificationType.match    => Icons.sports_soccer_rounded,
    NotificationType.promo    => Icons.local_offer_rounded,
    NotificationType.system   => Icons.notifications_rounded,
    NotificationType.payment  => Icons.account_balance_wallet_rounded,
    NotificationType.referral => Icons.people_rounded,
  };

  String _formatDate(DateTime d) {
    final now  = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}min';
    if (diff.inHours   < 24)  return '${diff.inHours}h';
    if (diff.inDays    < 7)   return '${diff.inDays}j';
    return AppDateFormatter.relative(d);
  }
}

// ─── Point non-lu pulsant ─────────────────────────────────────────────────────
class _UnreadDot extends StatefulWidget {
  @override
  State<_UnreadDot> createState() => _UnreadDotState();
}

class _UnreadDotState extends State<_UnreadDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (_, _) => Container(
      width: 8, height: 8,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: _pulse.value),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: _pulse.value * 0.5),
            blurRadius: 4 * _pulse.value,
            spreadRadius: 1,
          ),
        ],
      ),
    ),
  );
}
