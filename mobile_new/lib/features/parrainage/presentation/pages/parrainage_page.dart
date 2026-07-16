import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/referral_provider.dart';

class ParrainagePage extends ConsumerWidget {
  const ParrainagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(referralStatsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.35),
                blurRadius: 8, offset: const Offset(0, 3))]),
            child: const Icon(Icons.people_rounded, color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.cl.textP),
            children: const [
              TextSpan(text: 'Parrain'),
              TextSpan(text: 'age', style: TextStyle(color: Color(0xFFA78BFA))),
            ],
          )),
        ]),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFA78BFA))),
        error:   (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
        data: (stats) {
          final code       = stats['referral_code'] as String? ?? '------';
          final earnings   = (stats['total_earnings'] as num?)?.toInt() ?? 0;
          final canWithdraw = stats['can_withdraw'] as bool? ?? false;
          final minWithdraw = (stats['min_withdrawal'] as num?)?.toInt() ?? 2000;
          final commL1     = (stats['commission_l1'] as num?)?.toInt() ?? 500;
          final commL2     = (stats['commission_l2'] as num?)?.toInt() ?? 200;
          final s          = stats['stats'] as Map<String, dynamic>? ?? {};
          final totalL1    = (s['total_l1'] as num?)?.toInt() ?? 0;
          final premL1     = (s['premium_l1'] as num?)?.toInt() ?? 0;
          final totalL2    = (s['total_l2'] as num?)?.toInt() ?? 0;
          final premL2     = (s['premium_l2'] as num?)?.toInt() ?? 0;
          final l1List     = stats['l1_referrals'] as List<dynamic>? ?? [];
          final l2List     = stats['l2_referrals'] as List<dynamic>? ?? [];
          final hasParrain = (stats['has_referrer'] as bool?) ?? false;

          return RefreshIndicator(
            color: const Color(0xFFA78BFA),
            onRefresh: () async => ref.invalidate(referralStatsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [

                // ─── Solde + Code ──────────────────────────────────────────
                _EarningsBanner(
                  earnings:   earnings,
                  canWithdraw: canWithdraw,
                  minWithdraw: minWithdraw,
                  onWithdraw: () => context.push('/parrainage/retrait', extra: {
                    'earnings': earnings, 'min': minWithdraw,
                  }),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0),
                const SizedBox(height: 16),

                // ─── Mon code parrainage ───────────────────────────────────
                _ReferralCodeCard(code: code)
                  .animate().fadeIn(duration: 350.ms, delay: 80.ms)
                  .slideY(begin: 0.08, end: 0),
                const SizedBox(height: 16),

                // ─── Entrer code parrain (si pas encore de parrain) ────────
                if (!hasParrain) ...[
                  const _EnterCodeCard()
                    .animate().fadeIn(duration: 300.ms, delay: 130.ms),
                  const SizedBox(height: 16),
                ],

                // ─── Comment ça marche ─────────────────────────────────────
                _HowItWorksCard(commL1: commL1, commL2: commL2)
                  .animate().fadeIn(duration: 300.ms, delay: 160.ms),
                const SizedBox(height: 16),

                // ─── Stats filleuls ────────────────────────────────────────
                _StatsRow(totalL1: totalL1, premL1: premL1, totalL2: totalL2, premL2: premL2)
                  .animate().fadeIn(duration: 300.ms, delay: 200.ms),
                const SizedBox(height: 16),

                // ─── Liste filleuls L1 ─────────────────────────────────────
                if (l1List.isNotEmpty) ...[
                  _SectionLabel('FILLEULS DIRECTS (${l1List.length})'),
                  ...l1List.asMap().entries.map((e) => _FilleulTile(
                    pseudo:     e.value['pseudo']    as String? ?? '—',
                    plan:       e.value['plan']      as String? ?? 'free',
                    commission: (e.value['commission'] as num?)?.toInt() ?? 0,
                    isPaid:     e.value['is_paid']   as bool? ?? false,
                    joinedAt:   e.value['joined_at'] as String?,
                    level:      1,
                  ).animate(delay: Duration(milliseconds: e.key * 50))
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: -0.05, end: 0, duration: 280.ms, curve: Curves.easeOutCubic)),
                  const SizedBox(height: 8),
                ],

                // ─── Liste filleuls L2 ─────────────────────────────────────
                if (l2List.isNotEmpty) ...[
                  _SectionLabel('FILLEULS DE FILLEULS (${l2List.length})'),
                  ...l2List.asMap().entries.map((e) => _FilleulTile(
                    pseudo:     e.value['pseudo']    as String? ?? '—',
                    plan:       e.value['plan']      as String? ?? 'free',
                    commission: (e.value['commission'] as num?)?.toInt() ?? 0,
                    isPaid:     e.value['is_paid']   as bool? ?? false,
                    joinedAt:   e.value['joined_at'] as String?,
                    level:      2,
                  ).animate(delay: Duration(milliseconds: e.key * 50))
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: -0.05, end: 0, duration: 280.ms, curve: Curves.easeOutCubic)),
                  const SizedBox(height: 8),
                ],

                if (l1List.isEmpty && l2List.isEmpty)
                  _EmptyState(code: code)
                    .animate()
                    .scale(begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
                        duration: 450.ms, curve: Curves.easeOutBack)
                    .fadeIn(duration: 350.ms),

                // ─── Historique des gains ─────────────────────────────────
                const SizedBox(height: 8),
                const _HistorySection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── BANNIÈRE GAINS ──────────────────────────────────────────────────────────
class _EarningsBanner extends StatelessWidget {
  final int earnings, minWithdraw;
  final bool canWithdraw;
  final VoidCallback onWithdraw;

  const _EarningsBanner({
    required this.earnings, required this.minWithdraw,
    required this.canWithdraw, required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1040), Color(0xFF0D0820)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3), width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('MES GAINS PARRAINAGE', style: TextStyle(
        color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: earnings),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text(
            v.toLocaleString(),
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 6, bottom: 6),
          child: Text('FCFA', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            canWithdraw
              ? '✅ Retrait disponible !'
              : 'Encore ${(minWithdraw - earnings).toLocaleString()} FCFA pour retirer',
            style: TextStyle(
              color: canWithdraw ? AppColors.success : const Color(0xFFCBD5E1),
              fontSize: 12,
            ),
          ),
          if (!canWithdraw) ...[
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (earnings / minWithdraw).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: const Color(0xFF2A1A60),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFA78BFA)),
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ])),
        if (canWithdraw) ...[
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onWithdraw,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA78BFA),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            child: const Text('Retirer', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    ]),
  );
}

// ─── CODE PARRAINAGE ─────────────────────────────────────────────────────────
class _ReferralCodeCard extends StatelessWidget {
  final String code;
  const _ReferralCodeCard({required this.code});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(children: [
      Text('VOTRE CODE DE PARRAINAGE', style: TextStyle(
        color: context.cl.textS, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Code copié ! 📋'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFA78BFA).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3), width: 1.5)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(code, style: const TextStyle(
              color: Color(0xFFA78BFA), fontSize: 28,
              fontWeight: FontWeight.w800, letterSpacing: 6)),
            const SizedBox(width: 12),
            const Icon(Icons.copy_rounded, color: Color(0xFFA78BFA), size: 20),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Text('Appuyez pour copier · Partagez avec tes amis',
        style: TextStyle(color: context.cl.textM, fontSize: 11)),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showShareSheet(context, code),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Partager mon code'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA78BFA),
            foregroundColor: Colors.white,
          ),
        ),
      ),
    ]),
  );

  void _showShareSheet(BuildContext context, String code) {
    const purple = Color(0xFFA78BFA);
    final message = '🏆 Rejoins PronoWin et gagne avec les meilleurs pronostics !\n'
                    'Utilise mon code de parrainage : *$code*\n'
                    '👉 Télécharge l\'app : pronowin.com/download\n'
                    '💰 Tu m\'aides aussi à gagner des commissions !';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: ctx.cl.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: ctx.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Partager mon code', style: TextStyle(
            color: ctx.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Aperçu du message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: purple.withValues(alpha: 0.2)),
            ),
            child: Text(message, style: TextStyle(
              color: ctx.cl.textS, fontSize: 13, height: 1.5)),
          ),
          const SizedBox(height: 16),
          // Options de partage
          Row(children: [
            _ShareOption(
              icon: Icons.content_copy_rounded, label: 'Copier\nle message',
              color: AppColors.info,
              onTap: () {
                Clipboard.setData(ClipboardData(text: message));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Message copié ! Collez-le sur WhatsApp, SMS… 📤'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 3),
                ));
              },
            ),
            const SizedBox(width: 12),
            _ShareOption(
              icon: Icons.tag_rounded, label: 'Copier\nle code seul',
              color: purple,
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Code $code copié ! 📋'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
            const SizedBox(width: 12),
            _ShareOption(
              icon: Icons.sms_rounded, label: 'Message\nprêt à envoyer',
              color: AppColors.success,
              onTap: () {
                Clipboard.setData(ClipboardData(text: message));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Message copié ! Ouvrez WhatsApp et collez. ✅'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 3),
                ));
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── ENTRER CODE PARRAIN ─────────────────────────────────────────────────────
class _EnterCodeCard extends ConsumerStatefulWidget {
  const _EnterCodeCard();
  @override
  ConsumerState<_EnterCodeCard> createState() => _EnterCodeCardState();
}
class _EnterCodeCardState extends ConsumerState<_EnterCodeCard> {
  final _ctrl = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(applyCodeProvider);

    ref.listen<ApplyCodeState>(applyCodeProvider, (_, s) {
      if (s is ApplyCodeSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${s.referrerPseudo} est ton parrain !'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        ref.invalidate(referralStatsProvider);
        ref.read(applyCodeProvider.notifier).reset();
        setState(() => _expanded = false);
      }
      if (s is ApplyCodeError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(applyCodeProvider.notifier).reset();
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: context.cl.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: Column(children: [
        InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _expanded = !_expanded);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.card_giftcard_rounded, color: AppColors.primary, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vous avez un code parrain ?', style: TextStyle(
                  color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500)),
                Text('Entrez-le pour lier ton parrain', style: TextStyle(
                  color: context.cl.textM, fontSize: 11)),
              ])),
              Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: context.cl.textM, size: 20),
            ]),
          ),
        ),
        if (_expanded) Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.cl.border, width: 0.5))),
          child: Column(children: [
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(letterSpacing: 4, fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'EX: A1B2C3',
                prefixIcon: Icon(Icons.tag_rounded, color: context.cl.textM),
              ),
              onChanged: (v) => _ctrl.value = _ctrl.value.copyWith(
                text: v.toUpperCase(),
                selection: TextSelection.collapsed(offset: v.length),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: state is ApplyCodeLoading
                    ? null
                    : () {
                        if (_ctrl.text.trim().length < 4) return;
                        ref.read(applyCodeProvider.notifier).apply(_ctrl.text.trim());
                      },
                child: state is ApplyCodeLoading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Valider le code'),
              ),
            ),
          ]),
        ),
      ]),
      ),
    );
  }
}

// ─── COMMENT ÇA MARCHE ───────────────────────────────────────────────────────
class _HowItWorksCard extends StatelessWidget {
  final int commL1, commL2;
  const _HowItWorksCard({required this.commL1, required this.commL2});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('COMMENT ÇA MARCHE ?', style: TextStyle(
        color: context.cl.textS, fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 14),
      _Step(num: '1', color: AppColors.primary,
        text: 'Partagez ton code avec tes amis'),
      _Step(num: '2', color: const Color(0xFFA78BFA),
        text: 'Ils s\'inscrivent sur PronoWin'),
      _Step(num: '3', color: AppColors.success,
        text: 'Quand ils s\'abonnent Premium → +$commL1 FCFA pour toi'),
      _Step(num: '4', color: AppColors.info,
        text: 'Leurs filleuls Premium → +$commL2 FCFA supplémentaires'),
    ]),
  );
}

class _Step extends StatelessWidget {
  final String num, text; final Color color;
  const _Step({required this.num, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 26, height: 26,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(num, style: TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(
        color: context.cl.textS, fontSize: 13))),
    ]),
  );
}

// ─── STATS ROW ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final int totalL1, premL1, totalL2, premL2;
  const _StatsRow({required this.totalL1, required this.premL1, required this.totalL2, required this.premL2});

  @override
  Widget build(BuildContext context) => Row(children: [
    _StatChip(label: 'Filleuls\ndirects', value: totalL1, sub: '$premL1 Premium', color: const Color(0xFFA78BFA)),
    const SizedBox(width: 10),
    _StatChip(label: 'Filleuls\nindirects', value: totalL2, sub: '$premL2 Premium', color: AppColors.info),
    const SizedBox(width: 10),
    _StatChip(label: 'Total\nfilleuls', value: totalL1 + totalL2, sub: '${premL1 + premL2} Premium', color: AppColors.success),
  ]);
}

class _StatChip extends StatelessWidget {
  final String label, sub; final int value; final Color color;
  const _StatChip({required this.label, required this.value, required this.sub, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: context.cl.textM, fontSize: 11)),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: value),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text('$v', style: TextStyle(
              color: color, fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        Text(sub, style: TextStyle(color: context.cl.textM, fontSize: 10)),
      ]),
    ),
  );
}

// ─── TUILE FILLEUL ────────────────────────────────────────────────────────────
class _FilleulTile extends StatelessWidget {
  final String pseudo, plan;
  final int commission; final bool isPaid; final int level;
  final String? joinedAt;
  const _FilleulTile({required this.pseudo, required this.plan, required this.commission, required this.isPaid, required this.level, this.joinedAt});

  bool get _isNew {
    if (joinedAt == null) return false;
    final d = DateTime.tryParse(joinedAt!);
    if (d == null) return false;
    return DateTime.now().difference(d).inDays < 7;
  }

  static String _fmtDate(String iso) {
    try {
      final d   = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inDays == 0) return 'Aujourd\'hui';
      if (diff.inDays == 1) return 'Hier';
      if (diff.inDays < 7)  return 'Il y a ${diff.inDays}j';
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      Container(width: 36, height: 36,
        decoration: BoxDecoration(
          color: level == 1
            ? const Color(0xFFA78BFA).withValues(alpha: 0.12)
            : AppColors.info.withValues(alpha: 0.12),
          shape: BoxShape.circle),
        child: Center(child: Text(pseudo[0].toUpperCase(),
          style: TextStyle(
            color: level == 1 ? const Color(0xFFA78BFA) : AppColors.info,
            fontWeight: FontWeight.w700, fontSize: 15)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(pseudo, style: TextStyle(color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500)),
          if (_isNew) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: const Text('Nouveau', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w700))),
          ],
        ]),
        Text(
          joinedAt != null ? 'Niv. $level · ${_fmtDate(joinedAt!)}' : 'Niveau $level',
          style: TextStyle(color: level == 1 ? const Color(0xFFA78BFA) : AppColors.info,
            fontSize: 11, fontWeight: FontWeight.w500)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(plan == 'premium' ? '👑 Premium' : '• Gratuit',
          style: TextStyle(
            color: plan == 'premium' ? AppColors.warning : context.cl.textM,
            fontSize: 12, fontWeight: FontWeight.w500)),
        if (commission > 0)
          Text('+${commission.toLocaleString()} FCFA',
            style: TextStyle(
              color: isPaid ? AppColors.success : context.cl.textM,
              fontSize: 12, fontWeight: FontWeight.w700)),
        if (!isPaid && plan == 'premium')
          Text('En attente', style: TextStyle(color: context.cl.textM, fontSize: 10)),
      ]),
    ]),
  );
}

// ─── ÉTAT VIDE ────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String code;
  const _EmptyState({required this.code});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(children: [
      Icon(Icons.people_outline_rounded, color: context.cl.textM, size: 48),
      const SizedBox(height: 12),
      Text('Aucun filleul pour l\'instant', style: TextStyle(
        color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Partagez ton code pour commencer\nà gagner des commissions',
        style: TextStyle(color: context.cl.textS, fontSize: 13),
        textAlign: TextAlign.center),
    ]),
  );
}

// ─── OPTION DE PARTAGE ────────────────────────────────────────────────────────
class _ShareOption extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ShareOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
        ]),
      ),
    ),
  );
}

// ─── HISTORIQUE DES GAINS ─────────────────────────────────────────────────────
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(referralHistoryProvider);
    return histAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _SectionLabel('HISTORIQUE DES GAINS (${list.length})'),
          ...list.take(10).map((h) => _HistoryTile(
            pseudo:  h['pseudo'] as String? ?? '—',
            level:   (h['level'] as num?)?.toInt() ?? 1,
            amount:  (h['amount'] as num?)?.toInt() ?? 0,
            date:    h['date'] as String?,
          )),
        ]);
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final String pseudo; final int level, amount; final String? date;
  const _HistoryTile({required this.pseudo, required this.level, required this.amount, this.date});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Row(children: [
      Container(width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: const Icon(Icons.payments_rounded, color: AppColors.success, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$pseudo → abonnement Premium', style: TextStyle(
          color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w500)),
        if (date != null) Text(
          _fmtDate(date!),
          style: TextStyle(color: context.cl.textM, fontSize: 11)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('+${amount.toLocaleString()} FCFA', style: const TextStyle(
          color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w700)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (level == 1 ? const Color(0xFFA78BFA) : AppColors.info).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: Text('Niv. $level', style: TextStyle(
            color: level == 1 ? const Color(0xFFA78BFA) : AppColors.info,
            fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ]),
    ]),
  );

  static String _fmtDate(String iso) {
    try {
      final d   = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inDays < 7)  return 'Il y a ${diff.inDays}j';
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return ''; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 11,
      fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}

extension _IntFormat on int {
  String toLocaleString() {
    return toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
  }
}
