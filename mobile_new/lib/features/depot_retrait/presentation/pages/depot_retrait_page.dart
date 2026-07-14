import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/payment_provider.dart';
import '../widgets/transaction_tile_widget.dart';

class DepotRetraitPage extends ConsumerStatefulWidget {
  const DepotRetraitPage({super.key});

  @override
  ConsumerState<DepotRetraitPage> createState() => _DepotRetraitPageState();
}

class _DepotRetraitPageState extends ConsumerState<DepotRetraitPage> {
  final _formKey     = GlobalKey<FormState>();
  final _amountCtrl  = TextEditingController();
  final _xbetCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();

  TransactionType _opType  = TransactionType.deposit;
  String _selectedMethod   = 'orange_money';

  static const _methods = [
    {'key': 'orange_money', 'label': 'Orange Money', 'emoji': '🟠'},
    {'key': 'moov_money',   'label': 'Moov Money',   'emoji': '🔵'},
    {'key': 'mtn_momo',     'label': 'MTN MoMo',     'emoji': '🟡'},
  ];

  final _quickAmounts = [1000, 2000, 5000, 10000, 25000, 50000];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose(); _xbetCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exec        = ref.watch(paymentNotifierProvider);
    final wallet      = ref.watch(walletProvider);
    final txs         = ref.watch(transactionsProvider);
    final filteredTxs = ref.watch(filteredTransactionsProvider);

    // Calcule les totaux côté client à partir de l'historique
    final txList = txs.valueOrNull ?? [];
    final totalDeposits    = txList.where((t) => t.isDeposit  && t.status == TransactionStatus.completed).fold<double>(0, (s, t) => s + t.amount);
    final totalWithdrawals = txList.where((t) => !t.isDeposit && t.status == TransactionStatus.completed).fold<double>(0, (s, t) => s + t.amount);

    // Numéros MobCash depuis l'API (wallet)
    final walletNumbers = (wallet.valueOrNull?['mobcash_numbers'] as Map<String, dynamic>?) ?? {};

    ref.listen<PaymentExecState>(paymentNotifierProvider, (_, state) {
      if (state is PaymentSuccess) {
        _showSuccessSheet(state.data);
      } else if (state is PaymentError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message), backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    });

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          RichText(text: TextSpan(
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.cl.textP),
            children: const [TextSpan(text: 'Dépôt / '), TextSpan(text: 'Retrait', style: TextStyle(color: AppColors.primaryLight))],
          )),
        ]),
      ),
      body: Form(
        key: _formKey,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(walletProvider);
            ref.invalidate(transactionsProvider);
          },
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [

            // ─── Solde / Infos ────────────────────────────────────────
            wallet.when(
              loading: () => Shimmer.fromColors(baseColor: context.cl.surface, highlightColor: context.cl.border,
                child: Container(height: 80, decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(14)))),
              error: (_, _) => const SizedBox.shrink(),
              data: (w) => _WalletCard(
                walletData: w,
                totalDeposits: totalDeposits,
                totalWithdrawals: totalWithdrawals,
              ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.06, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),
            ),
            const SizedBox(height: 16),

            // ─── Onglets Dépôt / Retrait ──────────────────────────────
            _OperationToggle(current: _opType, onChanged: (t) {
              HapticFeedback.selectionClick();
              setState(() => _opType = t);
            }),
            const SizedBox(height: 20),

            // ─── Méthode Mobile Money ─────────────────────────────────
            _sectionLabel(context, 'Méthode de paiement'),
            ..._methods.map((m) => _MethodTile(
              emoji: m['emoji']!, label: m['label']!,
              selected: _selectedMethod == m['key'],
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedMethod = m['key']!);
              },
            )),
            const SizedBox(height: 16),

            // ─── Numéro MobCash à afficher ────────────────────────────
            _MobCashNumberCard(
              method: _selectedMethod,
              opType: _opType.name,
              number: (walletNumbers[_selectedMethod] as String?) ?? '…',
            ),
            const SizedBox(height: 16),

            // ─── ID 1xBet ─────────────────────────────────────────────
            _sectionLabel(context, 'Votre ID 1xBet'),
            TextFormField(
              controller: _xbetCtrl,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Ex: 123456789',
                prefixIcon: Icon(Icons.gamepad_rounded, size: 20, color: context.cl.textM),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'ID 1xBet requis' : null,
            ),
            const SizedBox(height: 4),
            Text(
              'Votre ID se trouve dans Profil Mon compte sur 1xBet',
              style: TextStyle(color: context.cl.textM, fontSize: 11),
            ),
            const SizedBox(height: 16),

            // ─── Numéro Mobile Money envoyeur ──────────────────────────
            _sectionLabel(context, 'Votre numéro Mobile Money'),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Ex: 70 00 00 00',
                prefixIcon: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Text('+226', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Numéro requis' : null,
            ),
            const SizedBox(height: 16),

            // ─── Montant ──────────────────────────────────────────────
            _sectionLabel(context, 'Montant (FCFA)'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(hintText: 'Ex: 5000'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Montant requis';
                  if (int.tryParse(v) == null || int.parse(v) < 500) return 'Minimum 500 FCFA';
                  return null;
                },
              )),
              const SizedBox(width: 10),
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.cl.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.cl.borderS, width: 0.5)),
                child: Text('FCFA', style: TextStyle(color: context.cl.textS, fontSize: 14))),
            ]),
            const SizedBox(height: 10),

            // Montants rapides
            Wrap(spacing: 8, runSpacing: 8, children: _quickAmounts.map((a) {
              final selected = _amountCtrl.text == a.toString();
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _amountCtrl.text = a.toString();
                  _amountCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _amountCtrl.text.length));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : context.cl.surfaceD,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppColors.primary : context.cl.borderS,
                      width: selected ? 1.2 : 0.5)),
                  child: Text('${a.toLocaleString()} F',
                    style: TextStyle(
                      color: selected ? AppColors.primary : context.cl.textS,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                ),
              );
            }).toList()),
            const SizedBox(height: 20),

            // ─── Info traitement ──────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(_opType),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.2), width: 0.5)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Traitement manuel', style: TextStyle(color: AppColors.info, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                      _opType == TransactionType.deposit
                        ? 'Après votre demande, envoyez le montant sur le numéro MobCash affiché. Votre dépôt sera confirmé sous 30 min ouvrables.'
                        : 'Votre demande sera traitée sous 30 min ouvrables. Le montant sera envoyé sur votre numéro Mobile Money.',
                      style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
                    ),
                  ])),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Bouton soumettre ─────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton.icon(
                onPressed: exec is PaymentLoading ? null : _submit,
                icon: exec is PaymentLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_opType == TransactionType.deposit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 20),
                label: Text(_opType == TransactionType.deposit ? 'Soumettre la demande de dépôt' : 'Soumettre la demande de retrait'),
              ),
            ).animate()
              .fadeIn(duration: 300.ms, delay: 200.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms, delay: 200.ms)
              .then(delay: 400.ms)
              .shimmer(duration: 1600.ms, color: Colors.white24)
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 3000.ms, delay: 2500.ms, color: Colors.white10),

            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: _sectionLabel(context, 'Historique récent')),
              if (txList.isNotEmpty)
                Text('${filteredTxs.length}/${txList.length} opération${txList.length > 1 ? 's' : ''}',
                  style: TextStyle(color: context.cl.textM, fontSize: 11)),
            ]),
            // Filtres historique
            if (txList.isNotEmpty) ...[
              const SizedBox(height: 8),
              _TxFilterBar(),
              const SizedBox(height: 8),
            ],
            txs.when(
              loading: () => Shimmer.fromColors(
                baseColor: context.cl.surface, highlightColor: context.cl.border,
                child: Column(children: List.generate(3, (_) => Container(
                  height: 64, margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: context.cl.surface,
                    borderRadius: BorderRadius.circular(12)))))),
              error: (_, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.2))),
                child: const Row(children: [
                  Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                  SizedBox(width: 10),
                  Text("Impossible de charger l'historique",
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
                ]),
              ),
              data: (_) => filteredTxs.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Icon(Icons.receipt_long_outlined, color: context.cl.textM, size: 36),
                      const SizedBox(height: 10),
                      Text('Aucune transaction', style: TextStyle(color: context.cl.textS, fontSize: 13)),
                    ]),
                  )
                : Column(children: filteredTxs.asMap().entries.map((e) =>
                    TransactionTileWidget(tx: e.value)
                      .animate(delay: Duration(milliseconds: e.key * 40))
                      .fadeIn(duration: 250.ms)
                      .slideX(begin: 0.04, end: 0),
                  ).toList()),
            ),
          ],
        ),        // ListView
        ),        // RefreshIndicator
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t.toUpperCase(), style: TextStyle(color: context.cl.textS, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(paymentNotifierProvider.notifier).submitManual(
        type:        _opType,
        amount:      double.parse(_amountCtrl.text),
        method:      _selectedMethod,
        xbetId:      _xbetCtrl.text.trim(),
        senderPhone: '+226${_phoneCtrl.text.trim()}',
      );
    }
  }

  void _showSuccessSheet(PaymentSuccessData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _SuccessSheet(
        data:   data,
        isDeposit: _opType == TransactionType.deposit,
        onDismiss: () {
          ref.read(paymentNotifierProvider.notifier).reset();
          ref.invalidate(transactionsProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ─── Sous-widgets ──────────────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  final Map<String, dynamic> walletData;
  final double totalDeposits;
  final double totalWithdrawals;
  const _WalletCard({required this.walletData, required this.totalDeposits, required this.totalWithdrawals});

  @override
  Widget build(BuildContext context) {
    final hasXbet = walletData['xbet_id'] != null;
    final pending = (walletData['pending_requests'] ?? 0) as int;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1540), Color(0xFF0D1030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.primaryLight, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Portefeuille MobCash',
                    style: TextStyle(color: Color(0xFF8892AA),
                        fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  hasXbet
                      ? 'ID 1xBet : ${walletData['xbet_id']}'
                      : 'Liez votre ID 1xBet ci-dessous',
                  style: TextStyle(
                    color: hasXbet ? const Color(0xFFE2E8F0) : const Color(0xFF8892AA),
                    fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            )),
            if (pending > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: AppColors.warning, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('$pending en attente',
                      style: const TextStyle(color: AppColors.warning,
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          if (hasXbet) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1E2A42), thickness: 0.5, height: 1),
            const SizedBox(height: 12),
            Row(children: [
              _WalletStat(label: 'Dépôts',    rawValue: totalDeposits,    color: AppColors.success),
              const SizedBox(width: 16),
              _WalletStat(label: 'Retraits',  rawValue: totalWithdrawals, color: AppColors.error),
              const SizedBox(width: 16),
              _WalletStatInt(label: 'En attente', rawValue: pending, color: AppColors.warning),
            ]),
          ],
        ],
      ),
    );
  }
}

String _fmtAmount(double v) {
  if (v == 0) return '–';
  final k = v >= 1000;
  final s = k ? (v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1) : v.toStringAsFixed(0);
  return k ? '${s}k F' : '$s F';
}

class _WalletStat extends StatelessWidget {
  final String label;
  final double rawValue;
  final Color color;
  const _WalletStat({required this.label, required this.rawValue, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: rawValue),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(
          _fmtAmount(v),
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      Text(label, style: const TextStyle(color: Color(0xFF8892AA), fontSize: 10)),
    ],
  );
}

class _WalletStatInt extends StatelessWidget {
  final String label;
  final int rawValue;
  final Color color;
  const _WalletStatInt({required this.label, required this.rawValue, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: rawValue),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(
          '$v',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      Text(label, style: const TextStyle(color: Color(0xFF8892AA), fontSize: 10)),
    ],
  );
}

class _MobCashNumberCard extends StatelessWidget {
  final String method, opType, number;
  const _MobCashNumberCard({required this.method, required this.opType, required this.number});

  @override
  Widget build(BuildContext context) {
    if (opType != 'deposit') return const SizedBox.shrink();
    final label  = method == 'orange_money' ? 'Orange Money' : method == 'moov_money' ? 'Moov Money' : 'MTN MoMo';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.send_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Text('Envoyez sur ce numéro $label :', style: TextStyle(color: context.cl.textS, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(number, style: const TextStyle(color: AppColors.primaryLight, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié !'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)));
            },
            child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 16)),
          ),
        ]),
      ]),
    );
  }
}

class _OperationToggle extends StatelessWidget {
  final TransactionType current;
  final void Function(TransactionType) onChanged;
  const _OperationToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDeposit = current == TransactionType.deposit;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderS, width: 0.5),
      ),
      child: Row(children: [
        _ToggleTab(
          label: 'Dépôt',
          icon: Icons.arrow_downward_rounded,
          active: isDeposit,
          activeColor: AppColors.success,
          onTap: () => onChanged(TransactionType.deposit),
        ),
        _ToggleTab(
          label: 'Retrait',
          icon: Icons.arrow_upward_rounded,
          active: !isDeposit,
          activeColor: AppColors.error,
          onTap: () => onChanged(TransactionType.withdrawal),
        ),
      ]),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _ToggleTab({required this.label, required this.icon,
      required this.active, required this.activeColor, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? LinearGradient(
            colors: [activeColor.withValues(alpha: 0.18), activeColor.withValues(alpha: 0.06)],
          ) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16,
              color: active ? activeColor : context.cl.textS),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(
              color: active ? activeColor : context.cl.textS,
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    ),
  );
}

class _MethodTile extends StatelessWidget {
  final String emoji, label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
      required this.emoji, required this.label,
      required this.selected, required this.onTap});

  Color get _methodColor {
    if (label.contains('Orange')) return const Color(0xFFFF6B00);
    if (label.contains('Moov'))   return const Color(0xFF0066CC);
    return const Color(0xFFFFCC00);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: selected ? LinearGradient(
          colors: [_methodColor.withValues(alpha: 0.12), _methodColor.withValues(alpha: 0.04)],
        ) : null,
        color: selected ? null : context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? _methodColor.withValues(alpha: 0.6) : context.cl.border,
          width: selected ? 1.5 : 0.5,
        ),
        boxShadow: selected ? [
          BoxShadow(
            color: _methodColor.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ] : [],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: selected
                ? _methodColor.withValues(alpha: 0.15)
                : context.cl.surfaceD,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(emoji,
              style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(
              color: selected ? _methodColor : context.cl.textP,
              fontSize: 14, fontWeight: FontWeight.w600)),
            Text('Transfert instantané',
                style: TextStyle(
                    color: context.cl.textM, fontSize: 10)),
          ],
        )),
        if (selected)
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: _methodColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _methodColor.withValues(alpha: 0.4), blurRadius: 6),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
          )
        else
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.cl.borderS, width: 1.5),
            ),
          ),
      ]),
    ),
  );
}

// ─── Feuille de succès ─────────────────────────────────────────────────────────

class _SuccessSheet extends StatefulWidget {
  final PaymentSuccessData data;
  final bool isDeposit;
  final VoidCallback onDismiss;
  const _SuccessSheet({required this.data, required this.isDeposit, required this.onDismiss});

  @override
  State<_SuccessSheet> createState() => _SuccessSheetState();
}

class _SuccessSheetState extends State<_SuccessSheet> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scaleAnim;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final isDeposit = widget.isDeposit;
    final mobcash   = widget.data.mobcashNumber;

    return Container(
      decoration: BoxDecoration(
        color: cl.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Handle
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: cl.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 28),

        // Checkmark animé
        ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                AppColors.success.withValues(alpha: 0.2),
                AppColors.success.withValues(alpha: 0.0),
              ]),
              shape: BoxShape.circle,
            ),
            child: Center(child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.success.withValues(alpha: 0.4),
                    blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
            )),
          ),
        ),
        const SizedBox(height: 20),

        FadeTransition(
          opacity: _fadeAnim,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              isDeposit ? 'Demande de dépôt soumise !' : 'Demande de retrait soumise !',
              style: TextStyle(color: cl.textP, fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isDeposit
                ? 'Votre demande a bien été enregistrée.\nEnvoyez maintenant le montant sur le numéro ci-dessous.'
                : 'Votre demande a bien été enregistrée.\nNous allons traiter votre retrait sous peu.',
              style: TextStyle(color: cl.textS, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // Numéro MobCash (dépôt uniquement)
        if (isDeposit && mobcash != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primary.withValues(alpha: 0.1),
                AppColors.primary.withValues(alpha: 0.04),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(children: [
              Row(children: [
                Icon(Icons.send_rounded, color: AppColors.primary, size: 14),
                const SizedBox(width: 6),
                Text('Numéro de réception', style: TextStyle(color: cl.textS, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  mobcash,
                  style: const TextStyle(color: AppColors.primaryLight, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: mobcash));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Numéro copié dans le presse-papier !'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Délai de traitement
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.schedule_rounded, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Traitement sous 30 minutes ouvrables.',
              style: TextStyle(color: cl.textS, fontSize: 12),
            )),
          ]),
        ),
        const SizedBox(height: 24),

        // CTA
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.onDismiss();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_rounded, size: 20),
              const SizedBox(width: 8),
              const Text('Compris, fermer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Filtre historique ────────────────────────────────────────────────────────
class _TxFilterBar extends ConsumerWidget {
  const _TxFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeFilter = ref.watch(txTypeFilterProvider);
    final statFilter = ref.watch(txStatusFilterProvider);

    final filters = <String, VoidCallback>{
      'Tous': () {
        ref.read(txTypeFilterProvider.notifier).state  = null;
        ref.read(txStatusFilterProvider.notifier).state = null;
      },
      'Dépôts': () {
        ref.read(txTypeFilterProvider.notifier).state  = TransactionType.deposit;
        ref.read(txStatusFilterProvider.notifier).state = null;
      },
      'Retraits': () {
        ref.read(txTypeFilterProvider.notifier).state  = TransactionType.withdrawal;
        ref.read(txStatusFilterProvider.notifier).state = null;
      },
      'En attente': () {
        ref.read(txTypeFilterProvider.notifier).state  = null;
        ref.read(txStatusFilterProvider.notifier).state = TransactionStatus.pending;
      },
    };

    bool isActive(String label) {
      if (label == 'Tous')        return typeFilter == null && statFilter == null;
      if (label == 'Dépôts')     return typeFilter == TransactionType.deposit;
      if (label == 'Retraits')   return typeFilter == TransactionType.withdrawal;
      if (label == 'En attente') return statFilter == TransactionStatus.pending;
      return false;
    }

    Color chipColor(String label) {
      if (label == 'Dépôts')     return AppColors.success;
      if (label == 'Retraits')   return AppColors.error;
      if (label == 'En attente') return AppColors.warning;
      return AppColors.primary;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.entries.map((e) {
          final active = isActive(e.key);
          final color  = chipColor(e.key);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              e.value();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.12) : context.cl.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? color : context.cl.border,
                  width: active ? 1 : 0.5)),
              child: Text(e.key,
                style: TextStyle(
                  color: active ? color : context.cl.textS,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

extension on int {
  String toLocaleString() {
    final s = toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
