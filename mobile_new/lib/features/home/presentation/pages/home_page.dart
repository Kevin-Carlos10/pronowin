import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/pronostics/presentation/providers/pronostics_provider.dart';
import '../../../../features/pronostics/presentation/widgets/match_card_widget.dart';
import '../../../../features/notifications/presentation/providers/notification_service.dart';
import '../../../../shared/widgets/skeletons.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState    = ref.watch(authProvider);
    final matchesAsync = ref.watch(matchesProvider);
    final unread       = ref.watch(unreadCountProvider);
    final isPremium    = authState is AuthAuthenticated && authState.user.isPremium;
    final pseudo       = authState is AuthAuthenticated ? authState.user.pseudo : 'Parieur';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(matchesProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [

              // ─── Header ─────────────────────────────────────────
              _Header(pseudo: pseudo, isPremium: isPremium, unread: unread,
                onNotifTap: () => context.push('/notifications'))
                .animate().fadeIn(duration: 300.ms).slideY(begin: -0.04, end: 0),
              const SizedBox(height: 16),

              // ─── Plan banner ─────────────────────────────────────
              if (!isPremium) _UpgradeBanner(onTap: () => context.push('/compte'))
                .animate(delay: 80.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0),
              if (!isPremium) const SizedBox(height: 16),

              // ─── Pub 1xBet ───────────────────────────────────────
              _AdBanner()
                .animate(delay: 120.ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),
              const SizedBox(height: 16),

              // ─── Actions rapides ─────────────────────────────────
              _QuickActions(),
              const SizedBox(height: 20),

              // ─── Stats du jour ────────────────────────────────────
              matchesAsync.isLoading
                ? const HomeStatsSkeleton()
                : _DayStats(matchesAsync: matchesAsync)
                    .animate(delay: 200.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0),
              const SizedBox(height: 20),

              // ─── Pronostics du jour (3 premiers) ─────────────────
              Row(children: [
                Expanded(child: Text('PRONOSTICS DU JOUR', style: TextStyle(
                  color: context.cl.textS, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1))),
                TextButton(
                  onPressed: () => context.push('/pronostics'),
                  child: const Text('Voir tout', style: TextStyle(fontSize: 12)),
                ),
              ]).animate(delay: 250.ms).fadeIn(duration: 300.ms),
              matchesAsync.when(
                loading: () => const Column(children: [
                  MatchCardSkeleton(),
                  MatchCardSkeleton(),
                ]),
                error: (_, _) => const SizedBox.shrink(),
                data: (matches) => matches.isEmpty
                  ? const _HomeEmptyState()
                      .animate(delay: 300.ms).fadeIn(duration: 400.ms)
                  : Column(
                      children: matches.take(3).toList().asMap().entries.map((e) =>
                        MatchCardWidget(match: e.value, isPremiumUser: isPremium)
                          .animate(delay: Duration(milliseconds: 300 + e.key * 70))
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                      ).toList(),
                    ),
              ),
              const SizedBox(height: 20),

              // ─── Code parrainage mini ─────────────────────────────
              _ReferralMini(authState: authState)
                .animate(delay: 500.ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String pseudo; final bool isPremium; final int unread;
  final VoidCallback onNotifTap;
  const _Header({required this.pseudo, required this.isPremium, required this.unread, required this.onNotifTap});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 36, height: 36,
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 20)),
    const SizedBox(width: 10),
    RichText(text: TextSpan(
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.cl.textP),
      children: const [TextSpan(text: 'Prono'), TextSpan(text: 'Win', style: TextStyle(color: AppColors.primaryLight))],
    )),
    const Spacer(),
    // Badge notifications
    Stack(clipBehavior: Clip.none, children: [
      IconButton(
        icon: Icon(Icons.notifications_none_rounded, color: context.cl.textS),
        onPressed: onNotifTap,
      ),
      if (unread > 0) Positioned(top: 6, right: 6,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
          child: Container(
            key: ValueKey(unread),
            width: 16, height: 16,
            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
            child: Center(child: Text('$unread',
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
        )),
    ]),
  ]);
}

class _UpgradeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _UpgradeBanner({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x40E8541A), blurRadius: 16, offset: Offset(0, 6))]),
      child: Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Plan Gratuit', style: TextStyle(color: Colors.white70, fontSize: 11)),
          SizedBox(height: 2),
          Text('Passez Premium', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Text('Pronostics VIP illimités', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.5)),
          child: const Text('Upgrader', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 2000.ms, color: Colors.white24, delay: 800.ms),
      ]),
    ),
  );
}

class _AdBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      const Icon(Icons.campaign_rounded, color: AppColors.primaryLight, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PUB', style: TextStyle(color: context.cl.textM, fontSize: 9, letterSpacing: 1)),
        Text('1xBet Bonus 200% sur votre 1er dépôt', style: TextStyle(color: context.cl.textS, fontSize: 12)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 0.5)),
        child: const Text('Voir', style: TextStyle(color: AppColors.primary, fontSize: 11)),
      ),
    ]),
  );
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.workspace_premium_rounded, 'Premium',         AppColors.success,        '/compte'),
      (Icons.people_rounded,            'Parrainage',      const Color(0xFFA78BFA),  '/compte'),
      (Icons.play_lesson_rounded,       'Tutoriels',       AppColors.info,           '/tutoriels'),
    ];
    return Row(
      children: actions.asMap().entries.map((e) {
        final (i, a) = (e.key, e.value);
        return Expanded(child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            context.push(a.$4);
          },
          child: Container(
            margin: EdgeInsets.only(right: i < actions.length - 1 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Column(children: [
              Icon(a.$1, color: a.$3, size: 24),
              const SizedBox(height: 6),
              Text(a.$2, style: TextStyle(color: context.cl.textS, fontSize: 10),
                textAlign: TextAlign.center, maxLines: 2),
            ]),
          ),
        ).animate(delay: Duration(milliseconds: 160 + i * 50))
          .fadeIn(duration: 280.ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic));
      }).toList(),
    );
  }
}

class _DayStats extends StatelessWidget {
  final AsyncValue matchesAsync;
  const _DayStats({required this.matchesAsync});
  @override
  Widget build(BuildContext context) {
    final total = matchesAsync.valueOrNull?.length ?? 0;
    final free  = matchesAsync.valueOrNull?.where((m) => !m.isPremium).length ?? 0;
    final vip   = total - free;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Row(children: [
        _Stat(value: total, label: 'Matchs',         color: AppColors.info),
        _DividerWidget(),
        _Stat(value: free,  label: 'Gratuits',        color: AppColors.success),
        _DividerWidget(),
        _Stat(value: vip,   label: 'VIP',             color: AppColors.primaryLight),
        _DividerWidget(),
        _Stat(value: 87,    label: 'Taux réussite %', color: AppColors.warning),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('$v',
        style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
    ),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: context.cl.textM, fontSize: 10),
      textAlign: TextAlign.center),
  ]));
}

class _DividerWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 36, color: context.cl.border,
    margin: const EdgeInsets.symmetric(horizontal: 4));
}

class _ReferralMini extends StatelessWidget {
  final dynamic authState;
  const _ReferralMini({required this.authState});
  @override
  Widget build(BuildContext context) {
    final code = authState is AuthAuthenticated ? authState.user.referralCode : 'PRONO00';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Row(children: [
        const Icon(Icons.people_rounded, color: Color(0xFFA78BFA), size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Votre code parrainage', style: TextStyle(color: context.cl.textS, fontSize: 11)),
          Text(code, style: const TextStyle(color: AppColors.primaryLight, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ])),
        GestureDetector(
          onTap: () => context.push('/compte'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFA78BFA).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: const Text('Gérer', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.0),
              ]),
            ),
          ),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1.5),
            ),
            child: const Center(child: Text('⚽', style: TextStyle(fontSize: 30))),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Aucun pronostic aujourd\'hui',
          style: TextStyle(color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Nos experts préparent les meilleures analyses.\nRevenez plus tard !',
          style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
          textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => context.push('/pronostics'),
          icon: const Icon(Icons.search_rounded, size: 15),
          label: const Text('Explorer tous les matchs', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}
