import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/referral_provider.dart';

class RetraitParrainagePage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? data;
  const RetraitParrainagePage({super.key, this.data});
  @override
  ConsumerState<RetraitParrainagePage> createState() => _RetraitPageState();
}

class _RetraitPageState extends ConsumerState<RetraitParrainagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _phoneCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _method    = 'orange_money';

  final _countries = [
    {'flag': '🇧🇫', 'code': '+226', 'digits': 8},
    {'flag': '🇨🇮', 'code': '+225', 'digits': 10},
    {'flag': '🇸🇳', 'code': '+221', 'digits': 9},
    {'flag': '🇲🇱', 'code': '+223', 'digits': 8},
  ];
  Map<String, dynamic> _country = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _country = _countries[0];
    final earnings = (widget.data?['earnings'] as num?)?.toInt() ?? 0;
    _amountCtrl.text = earnings.toString();
  }

  @override
  void dispose() {
    _tab.dispose(); _phoneCtrl.dispose(); _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final earnings   = (widget.data?['earnings'] as num?)?.toInt() ?? 0;
    final minWithdraw = (widget.data?['min'] as num?)?.toInt() ?? 2000;
    final withdrawState = ref.watch(withdrawProvider);

    ref.listen<WithdrawState>(withdrawProvider, (_, s) {
      if (s is WithdrawSuccess) _showSuccess(s.message);
      if (s is WithdrawError)   _showError(s.message);
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Retirer mes gains'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Color(0xFFA78BFA),
          labelColor:     Color(0xFFA78BFA),
          unselectedLabelColor: context.cl.textS,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android_rounded, size: 16), text: 'Mobile Money'),
            Tab(icon: Icon(Icons.workspace_premium_rounded, size: 16), text: 'Crédit Premium'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildMobileMoneyTab(earnings, minWithdraw, withdrawState),
          _buildCreditTab(earnings, withdrawState),
        ],
      ),
    );
  }

  Widget _buildMobileMoneyTab(int earnings, int minWithdraw, WithdrawState state) {
    return ListView(padding: const EdgeInsets.all(20), children: [

      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFA78BFA).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3))),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFA78BFA), size: 24),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Solde disponible', style: TextStyle(color: context.cl.textS, fontSize: 12)),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: earnings),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text('$v FCFA', style: const TextStyle(
                color: Color(0xFFA78BFA), fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ]),
        ]),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0),
      const SizedBox(height: 20),

      _FieldLabel('Montant à retirer (FCFA)'),
      TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '$minWithdraw',
          prefixIcon: Icon(Icons.payments_rounded, size: 20, color: context.cl.textM),
          helperText: 'Minimum $minWithdraw FCFA',
          helperStyle: TextStyle(color: context.cl.textM, fontSize: 11),
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Méthode de paiement'),
      ...['orange_money', 'moov_money', 'mtn_momo'].map((m) => _MethodTile(
        method: m,
        selected: _method == m,
        onTap: () => setState(() => _method = m),
      )),
      const SizedBox(height: 20),

      _FieldLabel('Numéro de réception'),
      Row(children: [
        GestureDetector(
          onTap: _showCountryPicker,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            decoration: BoxDecoration(
              color: context.cl.surfaceD, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cl.borderS, width: 0.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_country['flag'] as String, style: const TextStyle(fontSize: 20)),
              SizedBox(width: 6),
              Text(_country['code'] as String, style: TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
              SizedBox(width: 4),
              Icon(Icons.arrow_drop_down_rounded, color: context.cl.textM, size: 18),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_country['digits'] as int),
          ],
          decoration: const InputDecoration(hintText: '70 00 00 00'),
        )),
      ]),
      const SizedBox(height: 28),

      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton.icon(
          onPressed: (state is WithdrawLoading) ? null : _submitMobileMoney,
          icon: state is WithdrawLoading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 20),
          label: const Text('Demander le virement'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA78BFA)),
        ),
      ),
    ]);
  }

  Widget _buildCreditTab(int earnings, WithdrawState state) {
    final premiumDays = ((earnings / 5000) * 30).floor();

    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
        child: Column(children: [
          const Icon(Icons.workspace_premium_rounded, color: AppColors.primaryLight, size: 40),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: premiumDays),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text('$v jours Premium', style: const TextStyle(
              color: AppColors.primaryLight, fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          Text('pour tes $earnings FCFA de gains', style: const TextStyle(
            color: Color(0xFFCBD5E1), fontSize: 14)),
          const SizedBox(height: 8),
          const Text('(1 000 FCFA = 6 jours Premium)', style: TextStyle(
            color: Color(0xFF8892AA), fontSize: 12)),
        ]),
      ).animate().fadeIn(duration: 400.ms)
       .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1),
           duration: 400.ms, curve: Curves.easeOutBack),
      const SizedBox(height: 20),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✅ Avantages du crédit Premium', style: TextStyle(
            color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('• Activation immédiate, sans attente\n'
               '• Ajouté à ton abonnement existant\n'
               '• Pas de frais de traitement',
            style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.6)),
        ]),
      ),
      const SizedBox(height: 28),

      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton.icon(
          onPressed: (state is WithdrawLoading || premiumDays < 1) ? null : _submitCredit,
          icon: state is WithdrawLoading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.workspace_premium_rounded, size: 20),
          label: Text('Convertir en $premiumDays jours Premium'),
        ),
      ),
    ]);
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
        Text('Choisis ton pays', style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        ..._countries.map((c) => ListTile(
          leading: Text(c['flag'] as String, style: TextStyle(fontSize: 24)),
          title: Text(c['code'] as String, style: TextStyle(color: context.cl.textP)),
          trailing: Text('${c['digits']} chiffres', style: TextStyle(color: context.cl.textM, fontSize: 12)),
          onTap: () { setState(() => _country = c); Navigator.pop(context); },
        )),
        const SizedBox(height: 12),
      ]),
    );
  }

  void _submitMobileMoney() {
    final amount = int.tryParse(_amountCtrl.text) ?? 0;
    if (amount < 1) { _showError('Entrez un montant valide.'); return; }
    if (_phoneCtrl.text.length < 7) { _showError('Numéro de téléphone invalide.'); return; }
    final phone = '${_country['code']}${_phoneCtrl.text.trim()}';
    ref.read(withdrawProvider.notifier).withdraw(
      amount: amount.toDouble(), method: _method, phone: phone, useAsCredit: false);
  }

  void _submitCredit() {
    final earnings = (widget.data?['earnings'] as num?)?.toInt() ?? 0;
    ref.read(withdrawProvider.notifier).withdraw(
      amount: earnings.toDouble(), method: '', phone: '', useAsCredit: true);
  }

  void _showSuccess(String msg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.cl.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 28),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.35),
                blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ).animate()
           .scale(begin: const Offset(0.55, 0.55), end: const Offset(1, 1),
               duration: 500.ms, curve: Curves.easeOutBack)
           .fadeIn(duration: 400.ms),
          const SizedBox(height: 20),
          Text('Demande envoyée !', style: TextStyle(
            color: context.cl.textP, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(msg, style: TextStyle(
            color: context.cl.textS, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () {
                ref.read(withdrawProvider.notifier).reset();
                ref.invalidate(referralStatsProvider);
                context.pop(); context.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Parfait, fermer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
    ref.read(withdrawProvider.notifier).reset();
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _MethodTile extends StatelessWidget {
  final String method; final bool selected; final VoidCallback onTap;
  const _MethodTile({required this.method, required this.selected, required this.onTap});

  String get _label => method == 'orange_money' ? '🟠 Orange Money'
      : method == 'moov_money' ? '🔵 Moov Money' : '🟡 MTN MoMo';

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.08) : context.cl.surfaceD,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? AppColors.primary : context.cl.borderS, width: selected ? 1.5 : 0.5)),
      child: Row(children: [
        Text(_label, style: TextStyle(color: context.cl.textP, fontSize: 14)),
        const Spacer(),
        if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
      ]),
    ),
  );
}
