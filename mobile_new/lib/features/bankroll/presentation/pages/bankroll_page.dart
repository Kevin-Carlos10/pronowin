import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bankroll_provider.dart';

class BankrollPage extends ConsumerWidget {
  const BankrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankrollAsync = ref.watch(bankrollProvider);

    return Scaffold(
      backgroundColor: context.cl.bg,
      body: bankrollAsync.when(
        loading: () => const _BankrollShimmer(),
        error:   (e, _) => _ErrorState(onRetry: () => ref.invalidate(bankrollProvider)),
        data: (bankroll) => bankroll == null
            ? _SetupView(onSetup: () => _showBudgetDialog(context, null))
            : _BankrollView(
                bankroll: bankroll,
                onSetBudget: () => _showBudgetDialog(context, bankroll),
                onReset:     () => _confirmReset(context, ref),
              ),
      ),
    );
  }

  Future<void> _showBudgetDialog(
    BuildContext context, BankrollData? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetSheet(existing: existing),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cl.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Réinitialiser ?',
            style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w700)),
        content: Text(
          'Ton solde sera remis à ton budget initial. L\'historique des paris reste conservé.',
          style: TextStyle(color: context.cl.textS, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: context.cl.textM))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post('/bankroll/reset');
        ref.invalidate(bankrollProvider);
        ref.invalidate(bankrollStatsProvider);
      } catch (_) {}
    }
  }
}

// ── Vue principale ────────────────────────────────────────────────────────────
class _BankrollView extends StatelessWidget {
  final BankrollData bankroll;
  final VoidCallback onSetBudget;
  final VoidCallback onReset;
  const _BankrollView({required this.bankroll, required this.onSetBudget, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final settled  = bankroll.bets.where((b) => b.result != null).toList();
    final pending  = bankroll.bets.where((b) => b.result == null).toList();
    final wins     = settled.where((b) => b.result == 'WIN').length;
    final winRate  = settled.isNotEmpty ? wins / settled.length * 100 : 0.0;
    final profit   = bankroll.currentBalance - bankroll.totalBudget;

    return CustomScrollView(slivers: [
      // ── AppBar ─────────────────────────────────────────────────────────────
      SliverAppBar(
        floating: true, snap: true,
        backgroundColor: context.cl.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.success, Color(0xFF34D399)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.35),
                  blurRadius: 8, offset: const Offset(0, 3))]),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: context.cl.textP),
            children: const [
              TextSpan(text: 'Bank'),
              TextSpan(text: 'roll',
                  style: TextStyle(color: AppColors.success)),
            ],
          )),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.tune_rounded, color: context.cl.textM, size: 20),
            onPressed: onSetBudget),
        ]),
      ),

      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Carte solde principal ────────────────────────────────────────
          _BalanceCard(bankroll: bankroll, profit: profit).animate()
            .fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 16),

          // ── Stats rapides ─────────────────────────────────────────────
          Row(children: [
            Expanded(child: _StatChip(
              label:  'Paris',
              value:  '${settled.length}',
              icon:   Icons.receipt_long_rounded,
              color:  AppColors.info,
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(
              label:  'Victoires',
              value:  '$wins',
              icon:   Icons.emoji_events_rounded,
              color:  AppColors.success,
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(
              label:  'Win rate',
              value:  '${winRate.toStringAsFixed(0)}%',
              icon:   Icons.trending_up_rounded,
              color:  winRate >= 50 ? AppColors.success : AppColors.warning,
            )),
          ]).animate(delay: 80.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 22),

          // ── Reset ─────────────────────────────────────────────────────
          GestureDetector(
            onTap: onReset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:  AppColors.error.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2), width: 0.8)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, color: AppColors.error, size: 16),
                SizedBox(width: 6),
                Text('Réinitialiser le solde', style: TextStyle(
                  color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ).animate(delay: 120.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 24),

          // ── Paris en attente ──────────────────────────────────────────
          if (pending.isNotEmpty) ...[
            _SectionHeader(title: 'En attente', count: pending.length, color: AppColors.warning),
            const SizedBox(height: 10),
            ...pending.asMap().entries.map((e) =>
              _BetCard(bet: e.value).animate(delay: Duration(milliseconds: e.key * 50))
                .fadeIn(duration: 280.ms)
                .slideY(begin: 0.06, end: 0, duration: 280.ms)
                ,
            ),
            const SizedBox(height: 20),
          ],

          // ── Historique réglé ──────────────────────────────────────────
          if (settled.isNotEmpty) ...[
            _SectionHeader(title: 'Historique', count: settled.length, color: context.cl.textM),
            const SizedBox(height: 10),
            ...settled.asMap().entries.map((e) =>
              _BetCard(bet: e.value).animate(delay: Duration(milliseconds: e.key * 40))
                .fadeIn(duration: 280.ms)
                ,
            ),
          ],

          const SizedBox(height: 100),
        ]),
      )),
    ]);
  }
}

// ── Carte solde ───────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final BankrollData bankroll;
  final double profit;
  const _BalanceCard({required this.bankroll, required this.profit});

  @override
  Widget build(BuildContext context) {
    final isProfit  = profit >= 0;
    final profitColor = isProfit ? AppColors.success : AppColors.error;
    final pct = bankroll.progressPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.15),
            AppColors.success.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Solde actuel', style: TextStyle(
                color: context.cl.textM, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              '${_formatAmount(bankroll.currentBalance)} ${bankroll.currency}',
              style: TextStyle(
                color: context.cl.textP, fontSize: 28,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Budget total', style: TextStyle(
                color: context.cl.textM, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              '${_formatAmount(bankroll.totalBudget)} ${bankroll.currency}',
              style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),

        const SizedBox(height: 16),

        // Barre de progression
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.success.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 1 ? AppColors.success : AppColors.warning),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Row(children: [
          Icon(isProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: profitColor, size: 15),
          const SizedBox(width: 4),
          Text(
            '${isProfit ? '+' : ''}${_formatAmount(profit)} ${bankroll.currency}',
            style: TextStyle(
              color:      profitColor,
              fontSize:   13,
              fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% du budget',
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ]),
      ]),
    );
  }
}

// ── Chip stat ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8)),
    child: Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(
          color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: context.cl.textM, fontSize: 10)),
    ]),
  );
}

// ── En-tête section ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int    count;
  final Color  color;
  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: TextStyle(
        color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
    const SizedBox(width: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  ]);
}

// ── Carte pari ────────────────────────────────────────────────────────────────
class _BetCard extends StatelessWidget {
  final BankrollBet bet;
  const _BetCard({required this.bet});

  @override
  Widget build(BuildContext context) {
    final isPending = bet.result == null;
    final isWin     = bet.result == 'WIN';
    final color     = isPending ? AppColors.warning
                    : isWin    ? AppColors.success
                    :             AppColors.error;
    final icon      = isPending ? Icons.hourglass_empty_rounded
                    : isWin    ? Icons.check_circle_rounded
                    :             Icons.cancel_rounded;

    return GestureDetector(
      onTap: () => context.push('/bankroll/bet/${bet.id}', extra: bet),
      child: Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:  context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isPending ? 0.25 : 0.35), width: 0.8)),
      child: Row(children: [
        // Icône résultat
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),

        // Infos match
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${bet.homeTeam} – ${bet.awayTeam}',
            style: TextStyle(color: context.cl.textP, fontSize: 13,
                fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(bet.predictionLabel,
            style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ])),
        const SizedBox(width: 8),

        // Montants
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('−${_formatAmount(bet.stakedAmount)}',
            style: TextStyle(color: context.cl.textP, fontSize: 12,
                fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          if (bet.profit != null)
            Text(
              '${bet.profit! >= 0 ? '+' : ''}${_formatAmount(bet.profit!)}',
              style: TextStyle(
                color: bet.profit! >= 0 ? AppColors.success : AppColors.error,
                fontSize: 12, fontWeight: FontWeight.w700))
          else
            Text('→ ${_formatAmount(bet.potentialGain)}',
              style: TextStyle(color: context.cl.textM, fontSize: 11)),
        ]),
      ]),
    ));
  }
}

// ── Vue setup (pas de bankroll) ───────────────────────────────────────────────
class _SetupView extends StatelessWidget {
  final VoidCallback onSetup;
  const _SetupView({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Column(children: [
      // AppBar minimaliste
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.success, Color(0xFF34D399)]),
              borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 17)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: context.cl.textP),
            children: const [
              TextSpan(text: 'Bank'),
              TextSpan(text: 'roll',
                  style: TextStyle(color: AppColors.success)),
            ],
          )),
        ]),
      ),
      Expanded(child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color:  AppColors.success.withValues(alpha: 0.1),
              shape:  BoxShape.circle,
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
            child: const Icon(Icons.savings_rounded,
                color: AppColors.success, size: 44)),
          const SizedBox(height: 24),
          Text('Configure ton bankroll', style: TextStyle(
              color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'Définis ton budget pour que PronoWin te suggère les mises optimales et suive ton évolution.',
            style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.55),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          _features(context),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: onSetup,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.success, Color(0xFF059669)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.4),
                  blurRadius: 16, offset: const Offset(0, 6))]),
              child: const Center(child: Text('Définir mon budget',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700))),
            ),
          ),
        ]).animate().fadeIn(duration: 400.ms)
          .scale(begin: const Offset(0.9, 0.9), duration: 400.ms,
              curve: Curves.easeOutCubic),
      ))),
    ]));
  }

  Widget _features(BuildContext context) {
    const items = [
      (Icons.bolt_rounded,       'Mises calculées selon ton solde et la confiance'),
      (Icons.auto_graph_rounded, 'Suivi du ROI et taux de réussite en temps réel'),
      (Icons.update_rounded,     'Solde mis à jour automatiquement à chaque résultat'),
    ];
    return Column(children: items.map((i) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(i.$1, color: AppColors.success, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(i.$2,
          style: TextStyle(color: context.cl.textS, fontSize: 13))),
      ]),
    )).toList());
  }
}

// ── Bottom sheet budget ───────────────────────────────────────────────────────
class _BudgetSheet extends ConsumerStatefulWidget {
  final BankrollData? existing;
  const _BudgetSheet({this.existing});
  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final _ctrl     = TextEditingController();
  String _currency = 'XOF';
  bool   _loading  = false;
  String? _error;

  static const _currencies = ['XOF', 'XAF', 'GNF', 'EUR'];
  static const _presets    = [5000, 10000, 25000, 50000, 100000];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _ctrl.text = widget.existing!.totalBudget.toStringAsFixed(0);
      _currency  = widget.existing!.currency;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final amount = double.tryParse(_ctrl.text.replaceAll(' ', ''));
    if (amount == null || amount < 100) {
      setState(() => _error = 'Entrez un montant valide (min 100)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/bankroll/budget',
          data: {'total_budget': amount, 'currency': _currency});
      if (!mounted) return;
      ref.invalidate(bankrollProvider);
      Navigator.pop(context);
    } catch (e) {
      setState(() { _error = 'Erreur : $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  context.cl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: context.cl.border,
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),

        Text(widget.existing == null ? 'Définir ton budget' : 'Modifier le budget',
          style: TextStyle(color: context.cl.textP, fontSize: 17,
              fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Ce montant sert de référence pour calculer les mises suggérées.',
          style: TextStyle(color: context.cl.textM, fontSize: 12),
          textAlign: TextAlign.center),

        const SizedBox(height: 20),

        // Montant
        TextField(
          controller:   _ctrl,
          keyboardType: TextInputType.number,
          style:        TextStyle(color: context.cl.textP, fontSize: 18,
              fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText:  'Ex: 50 000',
            hintStyle: TextStyle(color: context.cl.textM, fontWeight: FontWeight.w400),
            prefixIcon: Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.success, size: 20),
            suffixText:   _currency,
            suffixStyle: const TextStyle(color: AppColors.success,
                fontWeight: FontWeight.w700),
            filled: true, fillColor: context.cl.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.cl.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.success, width: 1.5)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.cl.border)),
          ),
        ),

        const SizedBox(height: 12),

        // Presets
        Wrap(spacing: 8, children: _presets.map((p) => GestureDetector(
          onTap: () { setState(() => _ctrl.text = '$p'); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:  AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
            child: Text('${_formatAmount(p.toDouble())}',
              style: const TextStyle(color: AppColors.success, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          ),
        )).toList()),

        const SizedBox(height: 12),

        // Devise
        Row(children: [
          Text('Devise :', style: TextStyle(color: context.cl.textM, fontSize: 13)),
          const SizedBox(width: 12),
          ..._currencies.map((c) => GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _currency = c); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:  _currency == c
                    ? AppColors.success.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _currency == c
                      ? AppColors.success
                      : context.cl.border,
                  width: 0.8)),
              child: Text(c, style: TextStyle(
                color:      _currency == c ? AppColors.success : context.cl.textM,
                fontSize:   12,
                fontWeight: _currency == c ? FontWeight.w700 : FontWeight.w400)),
            ),
          )),
        ]),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],

        const SizedBox(height: 20),

        GestureDetector(
          onTap: _loading ? null : _save,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.success, Color(0xFF059669)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color: AppColors.success.withValues(alpha: 0.35),
                blurRadius: 12, offset: const Offset(0, 5))]),
            child: Center(child: _loading
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Text('Enregistrer', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────
class _BankrollShimmer extends StatefulWidget {
  const _BankrollShimmer();
  @override
  State<_BankrollShimmer> createState() => _BankrollShimmerState();
}
class _BankrollShimmerState extends State<_BankrollShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 900.ms)..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
      child: Column(children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: context.cl.surface.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(20))),
        const SizedBox(height: 16),
        Row(children: List.generate(3, (_) => Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          height: 80,
          decoration: BoxDecoration(
            color: context.cl.surface.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(14)))))),
      ]),
    ),
  );
}

// ── Error ─────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.wifi_off_rounded, color: context.cl.textM, size: 42),
      const SizedBox(height: 12),
      Text('Impossible de charger', style: TextStyle(color: context.cl.textP,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextButton(onPressed: onRetry,
          child: const Text('Réessayer', style: TextStyle(color: AppColors.success))),
    ],
  ));
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _formatAmount(double amount) {
  if (amount.abs() >= 1000) {
    final s = amount.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return amount < 0 ? '-${buf.toString()}' : buf.toString();
  }
  return amount.toStringAsFixed(0);
}
