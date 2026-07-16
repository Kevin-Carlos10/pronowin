import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/subscription_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Numéro de réception des paiements mobiles
const _paymentPhone    = '0757123456';
const _paymentOperator = 'Orange Money / Wave';

// Indicatifs par pays
const _countries = [
  {'flag': '🇧🇫', 'name': 'Burkina Faso', 'code': '+226', 'digits': 8},
  {'flag': '🇨🇮', 'name': "Côte d'Ivoire", 'code': '+225', 'digits': 10},
  {'flag': '🇸🇳', 'name': 'Sénégal',      'code': '+221', 'digits': 9},
  {'flag': '🇲🇱', 'name': 'Mali',          'code': '+223', 'digits': 8},
  {'flag': '🇬🇳', 'name': 'Guinée',        'code': '+224', 'digits': 9},
  {'flag': '🇫🇷', 'name': 'France',        'code': '+33',  'digits': 9},
];

class ActiverPremiumPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? subData;
  const ActiverPremiumPage({super.key, this.subData});

  @override
  ConsumerState<ActiverPremiumPage> createState() => _ActiverPremiumPageState();
}

class _ActiverPremiumPageState extends ConsumerState<ActiverPremiumPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _picker = ImagePicker();

  // Paywall state
  bool   _showPaywall   = true;
  String _selectedPlan  = 'mensuel'; // 'mensuel' | 'xbet'

  // Onglet 1 Paiement direct
  final _amountCtrl = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  File?   _imagePayment;
  Map<String, dynamic> _selectedCountry = _countries[0]; // BF par défaut

  // Onglet 2 Code 1xBet
  final _xbetCtrl2 = TextEditingController();
  File?  _imageXbet;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _amountCtrl.text = (widget.subData?['premium_price'] ?? 5000).toString();
    // Rediriger si le profil est incomplet (filet de sécurité)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState is AuthAuthenticated && !authState.user.isProfileComplete) {
        context.replace('/compte/completer-profil');
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _amountCtrl.dispose(); _phoneCtrl.dispose();
    _xbetCtrl2.dispose();
    super.dispose();
  }

  void _goToForm(String plan) {
    setState(() {
      _selectedPlan = plan;
      _showPaywall  = false;
      _tab.index    = plan == 'xbet' ? 1 : 0;
    });
  }

  // ─── Sélectionner image ───────────────────────────────────────────────────
  Future<void> _showImagePicker(bool isPayment) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: context.cl.borderSoft, borderRadius: BorderRadius.circular(2))),
          Text('Ajouter une image', style: TextStyle(
            color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Choisis ta capture d\'écran', style: TextStyle(color: context.cl.textM, fontSize: 12)),
          const SizedBox(height: 12),
          _PickerOption(
            icon: Icons.photo_library_rounded, color: AppColors.primary,
            title: 'Galerie photo', subtitle: 'Choisir depuis tes photos',
            onTap: () async {
              Navigator.pop(context);
              final f = await _pickFrom(ImageSource.gallery);
              if (f != null) setState(() => isPayment ? _imagePayment = f : _imageXbet = f);
            },
          ),
          _PickerOption(
            icon: Icons.camera_alt_rounded, color: AppColors.info,
            title: 'Appareil photo', subtitle: 'Prendre une nouvelle photo',
            onTap: () async {
              Navigator.pop(context);
              final f = await _pickFrom(ImageSource.camera);
              if (f != null) setState(() => isPayment ? _imagePayment = f : _imageXbet = f);
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<File?> _pickFrom(ImageSource src) async {
    try {
      final p = await _picker.pickImage(
        source:       src,
        imageQuality: 75,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      return p != null ? File(p.path) : null;
    } catch (_) { return null; }
  }

  // ─── Sélecteur de pays ────────────────────────────────────────────────────
  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: context.cl.borderSoft, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Choisis ton pays', style: TextStyle(
              color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          SizedBox(height: 8),
          ..._countries.map((c) => ListTile(
            leading: Text(c['flag'] as String, style: TextStyle(fontSize: 24)),
            title: Text(c['name'] as String, style: TextStyle(color: context.cl.textP)),
            trailing: Text(c['code'] as String, style: const TextStyle(
              color: AppColors.primary, fontWeight: FontWeight.w600)),
            onTap: () {
              setState(() {
                _selectedCountry = c;
                _phoneCtrl.clear();
              });
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitState = ref.watch(submitProofProvider);

    ref.listen<SubmitProofState>(submitProofProvider, (_, state) {
      if (state is ProofSubmitted) _showSuccessDialog(state.estimatedTime);
      if (state is ProofError)     _showSnack(state.message, isError: true);
    });

    if (_showPaywall) return _buildPaywallPage();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => setState(() => _showPaywall = true),
        ),
        title: Text(_selectedPlan == 'xbet' ? 'Activation Code 1xBet' : 'Paiement Mobile'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.cl.textS,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android_rounded, size: 16), text: 'Paiement Mobile'),
            Tab(icon: Icon(Icons.confirmation_number_rounded, size: 16), text: 'Code 1xBet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPaymentTab(submitState),
          _buildXbetTab(submitState),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // PAGE PAYWALL (landing d'activation premium)
  // ══════════════════════════════════════════════════════
  Widget _buildPaywallPage() {
    final price = widget.subData?['premium_price'] ?? 5000;
    return _PaywallPage(
      price:          price,
      selectedPlan:   _selectedPlan,
      onSelectPlan:   (p) => setState(() => _selectedPlan = p),
      onConfirm:      () => _goToForm(_selectedPlan),
      onClose:        () => context.pop(),
    );
  }

  // ══════════════════════════════════════════════════════'
  // ONGLET PAIEMENT
  // ══════════════════════════════════════════════════════'
  Widget _buildPaymentTab(SubmitProofState submitState) {
    final price = widget.subData?['premium_price'] ?? 5000;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [

        // Numéro de destination — copiable
        _PaymentRecipientCard(price: price),
        const SizedBox(height: 20),

        // 1. Montant
        _FieldLabel('1. Montant envoyé (FCFA)'),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: '$price',
            prefixIcon: Icon(Icons.payments_rounded, size: 20, color: context.cl.textM),
            helperText: 'Montant exact que tu as envoyé',
            helperStyle: TextStyle(color: context.cl.textM, fontSize: 11),
          ),
        ),
        const SizedBox(height: 20),

        // 2. Numéro qui a effectué le transfert
        _FieldLabel('2. Numéro Mobile Money utilisé pour le transfert'),
        Text(
          'Entrez le numéro depuis lequel tu as envoyé l\'argent',
          style: TextStyle(color: context.cl.textM, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(children: [
          // Sélecteur pays
          GestureDetector(
            onTap: _showCountryPicker,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cl.borderSoft, width: 0.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_selectedCountry['flag'] as String, style: const TextStyle(fontSize: 20)),
                SizedBox(width: 6),
                Text(_selectedCountry['code'] as String, style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down_rounded, color: context.cl.textM, size: 18),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_selectedCountry['digits'] as int),
              ],
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '70 00 00 00',
                helperText: '${_selectedCountry['digits']} chiffres',
                helperStyle: TextStyle(color: context.cl.textM, fontSize: 11),
              ),
            ),
          ),
        ]),

        // Aperçu du numéro complet
        ValueListenableBuilder(
          valueListenable: _phoneCtrl,
          builder: (_, val, _) {
            if (val.text.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Numéro complet : ${_selectedCountry['code']}${val.text}',
                  style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 20),

        // 3. Capture d'écran
        _FieldLabel('3. Capture d\'écran de la confirmation'),
        _ImagePickerWidget(image: _imagePayment, onTap: () => _showImagePicker(true)),
        const SizedBox(height: 16),

        // Récapitulatif avant envoi
        if (_imagePayment != null && _phoneCtrl.text.isNotEmpty)
          _RecapCard(
            amount:  double.tryParse(_amountCtrl.text) ?? 0,
            phone:   '${_selectedCountry['code']}${_phoneCtrl.text}',
            xbetId:  '',
          ),
        const SizedBox(height: 20),

        // Bouton
        _SubmitButton(
          label:     'Envoyer la preuve',
          icon:      Icons.upload_rounded,
          isLoading: submitState is ProofLoading,
          enabled:   _imagePayment != null &&
                     _phoneCtrl.text.length >= 7,
          onTap:     _submitPayment,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  // ONGLET CODE 1xBET
  // ══════════════════════════════════════════════════════
  Widget _buildXbetTab(SubmitProofState submitState) {
    final promoCode = widget.subData?['promo_code'] ?? 'PRONOWIN2025';
    const purple    = Color(0xFFA78BFA);
    const purpleDark = Color(0xFF7C3AED);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [

        // ── Header ────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [purpleDark.withValues(alpha: 0.18), purple.withValues(alpha: 0.06)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: purple.withValues(alpha: 0.25), width: 0.8)),
          child: Column(children: [
            const _XbetLogo(size: 32),
            const SizedBox(height: 12),
            Text('Rejoins 1xBet', style: TextStyle(
              color: context.cl.textP, fontSize: 17,
              fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(
              'Crée ton compte avec notre code promo et obtenez l\'accès Premium gratuitement.',
              style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center),
          ]),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

        const SizedBox(height: 20),

        // ── Code promo ────────────────────────────────────────────
        _PromoCodeCard(promoCode: promoCode)
          .animate(delay: 80.ms).fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0),

        const SizedBox(height: 20),

        // ── Timeline des étapes ───────────────────────────────────
        _XbetSteps()
          .animate(delay: 140.ms).fadeIn(duration: 300.ms),

        const SizedBox(height: 24),

        // ── Séparateur "Ta soumission" ─────────────────────────
        Row(children: [
          Expanded(child: Divider(color: context.cl.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('VOTRE SOUMISSION', style: TextStyle(
              color: context.cl.textM, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1))),
          Expanded(child: Divider(color: context.cl.border, height: 1)),
        ]).animate(delay: 180.ms).fadeIn(duration: 250.ms),

        const SizedBox(height: 20),

        // ── Champ ID 1xBet stylisé ────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _xbetCtrl2.text.isNotEmpty
                ? purple.withValues(alpha: 0.5)
                : context.cl.border,
              width: _xbetCtrl2.text.isNotEmpty ? 1.5 : 0.5)),
          child: Row(children: [
            Container(
              width: 48, height: 56,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(13),
                  bottomLeft: Radius.circular(13))),
              child: const Icon(Icons.badge_rounded, color: purple, size: 22)),
            Expanded(
              child: TextField(
                controller: _xbetCtrl2,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: context.cl.textP, fontSize: 16,
                  fontWeight: FontWeight.w600, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'Ton ID 1xBet',
                  hintStyle: TextStyle(color: context.cl.textM,
                    fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16)),
              ),
            ),
            if (_xbetCtrl2.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: const Icon(Icons.check_circle_rounded,
                  color: purple, size: 20))
                  .animate().scale(
                    begin: const Offset(0, 0), end: const Offset(1, 1),
                    duration: 200.ms, curve: Curves.easeOutBack),
          ]),
        ).animate(delay: 200.ms).fadeIn(duration: 280.ms),

        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('Visible dans Profil → Mon compte sur 1xBet',
            style: TextStyle(color: context.cl.textM, fontSize: 11))),

        const SizedBox(height: 20),

        // ── Zone upload capture ────────────────────────────────────
        Text('Capture de ton profil 1xBet', style: TextStyle(
          color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _ImagePickerWidget(image: _imageXbet, onTap: () => _showImagePicker(false)),

        const SizedBox(height: 28),

        // ── Bouton soumettre ──────────────────────────────────────
        _XbetSubmitButton(
          isLoading: submitState is ProofLoading,
          enabled:   _imageXbet != null && _xbetCtrl2.text.isNotEmpty,
          onTap:     _submitXbet,
        ).animate(delay: 240.ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),
      ],
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────
  Future<void> _submitPayment() async {
    final phone = '${_selectedCountry['code']}${_phoneCtrl.text.trim()}';
    if (_phoneCtrl.text.trim().length < 7) {
      _showSnack('Numéro de téléphone trop court.', isError: true); return;
    }
    final base64 = await _toBase64(_imagePayment!);
    if (base64 == null) return;
    ref.read(submitProofProvider.notifier).submit(
      type:        'payment_screenshot',
      imageBase64: base64,
      xbetId:      '',
      amount:      double.tryParse(_amountCtrl.text) ?? 5000,
      senderPhone: phone,
    );
  }

  Future<void> _submitXbet() async {
    if (_xbetCtrl2.text.trim().isEmpty) {
      _showSnack('ID 1xBet requis.', isError: true); return;
    }
    final base64 = await _toBase64(_imageXbet!);
    if (base64 == null) return;
    ref.read(submitProofProvider.notifier).submit(
      type:        'xbet_account_screenshot',
      imageBase64: base64,
      xbetId:      _xbetCtrl2.text.trim(),
    );
  }

  Future<String?> _toBase64(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      _showSnack('Erreur lecture image: $e', isError: true);
      return null;
    }
  }

  void _showSuccessDialog(String estimatedTime) {
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
        padding: EdgeInsets.fromLTRB(24, 12, 24,
          MediaQuery.of(context).viewInsets.bottom + 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 28),
          // Icône animée
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.2),
                AppColors.primary.withValues(alpha: 0.0),
              ]),
              shape: BoxShape.circle,
            ),
            child: Center(child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 36),
            )),
          ).animate()
           .scale(begin: const Offset(0.55, 0.55), end: const Offset(1, 1),
               duration: 500.ms, curve: Curves.easeOutBack)
           .fadeIn(duration: 400.ms),
          const SizedBox(height: 20),
          Text('Preuve soumise !', style: TextStyle(
            color: context.cl.textP, fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Ta demande est en cours de vérification.',
            style: TextStyle(color: context.cl.textS, fontSize: 14),
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          // Délai estimé
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.schedule_rounded, color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Text('Activation sous $estimatedTime',
                style: const TextStyle(
                  color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.15))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notifications_rounded, color: AppColors.info, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Vous recevrez une notification push dès que ton Premium est activé.',
                style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(submitProofProvider.notifier).reset();
                ref.invalidate(currentSubscriptionProvider);
                context.pop();
                context.pop();
              },
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text('Compris, j\'attends la validation',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

// Logo 1xBet textuel — "1X" blanc + "BET" bleu, italique bold
class _XbetLogo extends StatelessWidget {
  final double size;
  const _XbetLogo({required this.size});

  @override
  Widget build(BuildContext context) => Transform(
    transform: Matrix4.skewX(-0.08),
    child: RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          height: 1,
        ),
        children: const [
          TextSpan(text: '1X', style: TextStyle(color: Colors.white)),
          TextSpan(text: 'BET', style: TextStyle(color: Color(0xFF4B8FE2))),
        ],
      ),
    ),
  );
}

// ─── Carte numéro de réception ────────────────────────────────────────────────
class _PaymentRecipientCard extends StatelessWidget {
  final dynamic price;
  const _PaymentRecipientCard({required this.price});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.12),
          AppColors.primary.withValues(alpha: 0.04),
        ],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.send_to_mobile_rounded, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Text('Envoie $price FCFA à ce numéro',
          style: const TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_paymentPhone, style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 2),
            Text(_paymentOperator, style: TextStyle(
              fontSize: 11, color: context.cl.textS)),
          ])),
          GestureDetector(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: _paymentPhone));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Numéro copié !'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text('Copier', style: TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('Puis remplissez le formulaire ci-dessous et joignez la capture d\'écran.',
        style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
    ]),
  );
}

class _RecapCard extends StatelessWidget {
  final double amount; final String phone, xbetId;
  const _RecapCard({required this.amount, required this.phone, required this.xbetId});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.25), width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.fact_check_rounded, color: AppColors.success, size: 16),
        SizedBox(width: 8),
        Text('Récapitulatif de ta demande', style: TextStyle(
          color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      _RecapRow('Montant',      '${amount.toStringAsFixed(0)} FCFA'),
      _RecapRow('N° envoyeur',  phone),
      if (xbetId.isNotEmpty) _RecapRow('ID 1xBet', xbetId),
    ]),
  );
}

class _RecapRow extends StatelessWidget {
  final String label, value;
  const _RecapRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label : ', style: TextStyle(color: context.cl.textM, fontSize: 12)),
      Text(value, style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _PickerOption extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, subtitle; final VoidCallback onTap;
  const _PickerOption({required this.icon, required this.color,
    required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(width: 40, height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 22)),
    title: Text(title, style: TextStyle(color: context.cl.textP, fontSize: 14)),
    subtitle: Text(subtitle, style: TextStyle(color: context.cl.textM, fontSize: 11)),
    onTap: onTap,
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _InfoCard({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 13, height: 1.5))),
    ]),
  );
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

class _ImagePickerWidget extends StatefulWidget {
  final File? image; final VoidCallback onTap;
  const _ImagePickerWidget({required this.image, required this.onTap});
  @override State<_ImagePickerWidget> createState() => _ImagePickerWidgetState();
}
class _ImagePickerWidgetState extends State<_ImagePickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }
  @override void dispose() { _pressCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) { _pressCtrl.reverse(); widget.onTap(); },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(scale: _scale, child: Container(
      height: 150,
      decoration: BoxDecoration(
        color: widget.image != null ? AppColors.success.withValues(alpha: 0.04) : context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.image != null ? AppColors.success.withValues(alpha: 0.4) : context.cl.borderSoft,
          width: widget.image != null ? 1.5 : 0.5)),
      child: widget.image != null
        ? Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.file(widget.image!, width: double.infinity, height: 150, fit: BoxFit.cover)),
            Positioned(top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('Ajoutée', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ]))),
            Positioned(bottom: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: const Text('Changer', style: TextStyle(color: Colors.white, fontSize: 11)))),
          ])
        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.add_photo_alternate_rounded, color: AppColors.primary, size: 26)),
            SizedBox(height: 8),
            Text('Appuyez pour ajouter', style: TextStyle(color: context.cl.textS, fontSize: 13)),
            SizedBox(height: 3),
            Text('Galerie ou appareil photo', style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ]),
    )),
  );
}

class _SubmitButton extends StatelessWidget {
  final String label; final IconData icon;
  final bool isLoading, enabled; final VoidCallback onTap;
  const _SubmitButton({required this.label, required this.icon,
    required this.isLoading, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton.icon(
      onPressed: (!isLoading && enabled) ? onTap : null,
      icon: isLoading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 20),
      label: Text(label),
    ),
  );
}

// ─── PROMO CODE CARD ──────────────────────────────────────────────────────────
class _PromoCodeCard extends StatefulWidget {
  final String promoCode;
  const _PromoCodeCard({required this.promoCode});
  @override State<_PromoCodeCard> createState() => _PromoCodeCardState();
}
class _PromoCodeCardState extends State<_PromoCodeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }
  @override void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) {
      _pressCtrl.reverse();
      HapticFeedback.lightImpact();
      Clipboard.setData(ClipboardData(text: widget.promoCode));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Code copié !'), behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2)));
    },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFFA78BFA)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
              child: const Text('CODE PROMO 1xBET', style: TextStyle(
                color: Colors.white70, fontSize: 10,
                letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(widget.promoCode, style: const TextStyle(
            color: Colors.white, fontSize: 32,
            fontWeight: FontWeight.w900, letterSpacing: 5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.copy_rounded, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('Appuyer pour copier',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    ),
  );
}

// ─── ÉTAPES 1xBET ─────────────────────────────────────────────────────────────
class _XbetSteps extends StatelessWidget {
  const _XbetSteps();

  static const _steps = [
    (Icons.language_rounded,      'Rendez-vous sur 1xBet',        "Ouvrez 1xbet.com ou l'app mobile"),
    (Icons.person_add_rounded,    'Crée ton compte',           "Entrez le code promo lors de l'inscription"),
    (Icons.account_balance_wallet_rounded, 'Effectuez un dépôt', 'Un dépôt initial est obligatoire pour valider ton compte 1xBet'),
    (Icons.photo_camera_rounded,  'Prends une capture de profil', 'Ton ID 1xBet doit être visible'),
    (Icons.upload_rounded,        'Soumets ci-dessous',         'ID + capture → validation sous 24h'),
  ];

  @override
  Widget build(BuildContext context) {
    const purple     = Color(0xFFA78BFA);
    const purpleDark = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COMMENT ÇA MARCHE', style: TextStyle(
            color: context.cl.textM, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 14),
          ...List.generate(_steps.length, (i) {
            final (icon, title, sub) = _steps[i];
            final isLast = i == _steps.length - 1;
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [purpleDark, purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: purple.withValues(alpha: 0.3),
                        blurRadius: 8, offset: const Offset(0, 3))]),
                    child: Icon(icon, color: Colors.white, size: 18)),
                  if (!isLast)
                    Expanded(child: Container(
                      width: 2, margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [purple.withValues(alpha: 0.4), purple.withValues(alpha: 0.05)],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter)))),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 8),
                      Text(title, style: TextStyle(
                        color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(sub, style: TextStyle(
                        color: context.cl.textS, fontSize: 12, height: 1.4)),
                    ]),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// ─── BOUTON SOUMETTRE 1xBET ────────────────────────────────────────────────────
class _XbetSubmitButton extends StatelessWidget {
  final bool isLoading, enabled;
  final VoidCallback onTap;
  const _XbetSubmitButton({
    required this.isLoading, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: (!isLoading && enabled) ? () {
        HapticFeedback.mediumImpact();
        onTap();
      } : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity, height: 54,
          decoration: BoxDecoration(
            gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF4C1D95), purple, Color(0xFFA78BFA)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
            color: enabled ? null : context.cl.surface,
            borderRadius: BorderRadius.circular(16),
            border: enabled ? null : Border.all(color: context.cl.border, width: 0.5),
            boxShadow: enabled ? [BoxShadow(
              color: purple.withValues(alpha: 0.4),
              blurRadius: 16, offset: const Offset(0, 6))] : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isLoading)
              const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(isLoading ? 'Envoi en cours…' : 'Soumettre la preuve',
              style: TextStyle(
                color: enabled ? Colors.white : context.cl.textM,
                fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYWALL PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _PaywallPage extends StatelessWidget {
  final int price;
  final String selectedPlan;
  final void Function(String) onSelectPlan;
  final VoidCallback onConfirm;
  final VoidCallback onClose;

  const _PaywallPage({
    required this.price,
    required this.selectedPlan,
    required this.onSelectPlan,
    required this.onConfirm,
    required this.onClose,
  });

  static const _features = [
    (Icons.star_rounded,          'Pronostics VIP illimités'),
    (Icons.psychology_rounded,    'Analyse IA par match'),
    (Icons.leaderboard_rounded,   'Classement & statistiques'),
    (Icons.account_balance_wallet_rounded, 'Suivi bankroll avancé'),
  ];

  static const _testimonials = [
    ("Grâce à PronoWin, j'ai doublé ma bankroll en 3 semaines !", 'Moussa K.', 'Dakar'),
    ("Les analyses IA sont vraiment précises, je recommande.", 'Adjoua F.', 'Abidjan'),
    ("Interface claire, pronostics de qualité, excellent service.", 'Seydou B.', 'Bamako'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _StadiumBgPainter())),
        SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHero(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(children: [
                  _buildFeatures(context),
                  const SizedBox(height: 24),
                  _buildPlanLabel(),
                  const SizedBox(height: 12),
                  _MensuelCard(
                    price: price, isSelected: selectedPlan == 'mensuel',
                    onTap: () => onSelectPlan('mensuel')),
                  const SizedBox(height: 10),
                  _XbetCard(
                    isSelected: selectedPlan == 'xbet',
                    onTap: () => onSelectPlan('xbet')),
                  const SizedBox(height: 20),
                  _TestimonialCarousel(items: _testimonials),
                  const SizedBox(height: 24),
                  _PaywallCTA(selectedPlan: selectedPlan, price: price, onTap: onConfirm),
                  const SizedBox(height: 14),
                  const Text(
                    'Activation vérifiée par notre équipe sous 24h.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Text('CGU', style: TextStyle(color: Colors.white30, fontSize: 10)),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('·', style: TextStyle(color: Colors.white24))),
                    Text('Confidentialité', style: TextStyle(color: Colors.white30, fontSize: 10)),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('·', style: TextStyle(color: Colors.white24))),
                    Text('Contact', style: TextStyle(color: Colors.white30, fontSize: 10)),
                  ]),
                ]),
              ),
            ],
          ),
        ),
        // Bouton fermer
        Positioned(top: 52, right: 12,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18)))),
      ]),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD97706), Color(0xFFF59E0B)]),
            borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('PRONOSTICS PREMIUM', style: TextStyle(
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ]),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.1),
            children: [
              TextSpan(text: 'PronoWin ', style: TextStyle(color: Colors.white)),
              TextSpan(text: 'PRO', style: TextStyle(
                color: Color(0xFFF59E0B),
                shadows: [Shadow(color: Color(0x80F59E0B), blurRadius: 12)])),
            ],
          ),
        ).animate(delay: 80.ms).fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 10),
        const Text(
          'Gérez tes pronostics avec les analyses\nVIP et le suivi bankroll professionnel.',
          style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ).animate(delay: 140.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 72, height: 26,
            child: Stack(children: List.generate(3, (i) => Positioned(
              left: i * 18.0,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: [const Color(0xFFE8541A), const Color(0xFF7C3AED), const Color(0xFF059669)][i],
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0A0E1A), width: 2)),
                child: Center(child: Text(
                  ['M', 'A', 'S'][i],
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
            )))),
          const SizedBox(width: 8),
          RichText(text: const TextSpan(
            children: [
              TextSpan(text: '2K+', style: TextStyle(
                color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.w800)),
              TextSpan(text: '  Utilisateurs Actifs', style: TextStyle(
                color: Colors.white54, fontSize: 13)),
            ],
          )),
        ]).animate(delay: 200.ms).fadeIn(duration: 350.ms),
      ]),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10, mainAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: _features.asMap().entries.map((e) {
        final (icon, label) = e.value;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
          child: Row(children: [
            const SizedBox(width: 10),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Color(0xFFF59E0B), size: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 2)),
          ]),
        ).animate(delay: Duration(milliseconds: 300 + e.key * 60))
          .fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
      }).toList(),
    );
  }

  Widget _buildPlanLabel() {
    return Row(children: [
      Expanded(child: Divider(color: Colors.white12, height: 1)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('CHOISISSEZ VOTRE OPTION', style: TextStyle(
          color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
      Expanded(child: Divider(color: Colors.white12, height: 1)),
    ]);
  }
}

// ─── PLAN MENSUEL ─────────────────────────────────────────────────────────────
class _MensuelCard extends StatelessWidget {
  final int price;
  final bool isSelected;
  final VoidCallback onTap;
  const _MensuelCard({required this.price, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
            ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
            width: isSelected ? 2 : 0.5),
          boxShadow: isSelected ? [BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 16, offset: const Offset(0, 4))] : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Mensuel', style: TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(6)),
                  child: const Text('LE PLUS POPULAIRE', style: TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
              ]),
              const SizedBox(height: 4),
              const Text('Paiement Mobile Money', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$price FCFA', style: const TextStyle(
                color: Color(0xFFF59E0B), fontSize: 22, fontWeight: FontWeight.w900)),
              const Text('/mois', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          const SizedBox(height: 10),
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFF59E0B) : Colors.white24,
                  width: 1.5)),
              child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                : null),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'Orange Money  ·  Wave  ·  MTN  ·  Moov',
              style: TextStyle(color: Colors.white54, fontSize: 11))),
          ]),
        ]),
      ),
    );
  }
}

// ─── PLAN CODE 1xBET ──────────────────────────────────────────────────────────
class _XbetCard extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  const _XbetCard({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? purple.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? purple : Colors.white12,
            width: isSelected ? 2 : 0.5),
          boxShadow: isSelected ? [BoxShadow(
            color: purple.withValues(alpha: 0.2),
            blurRadius: 16, offset: const Offset(0, 4))] : null),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Code 1xBet', style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: purple.withValues(alpha: 0.5), width: 0.5)),
                child: const Text('GRATUIT', style: TextStyle(
                  color: Color(0xFFA78BFA), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
            ]),
            const SizedBox(height: 4),
            const Text("Inscris-toi sur 1xBet avec notre code", style: TextStyle(
              color: Colors.white54, fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: isSelected ? purple : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? purple : Colors.white24,
                width: 1.5)),
            child: isSelected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
              : null),
        ]),
      ),
    );
  }
}

// ─── TESTIMONIAL CAROUSEL ─────────────────────────────────────────────────────
class _TestimonialCarousel extends StatefulWidget {
  final List<(String, String, String)> items;
  const _TestimonialCarousel({required this.items});
  @override State<_TestimonialCarousel> createState() => _TestimonialCarouselState();
}
class _TestimonialCarouselState extends State<_TestimonialCarousel> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final (quote, name, city) = widget.items[_idx];
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim, child: SlideTransition(
            position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
            child: child)),
        child: Container(
          key: ValueKey(_idx),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.format_quote_rounded, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(height: 8),
            Text(quote, style: const TextStyle(
              color: Colors.white70, fontSize: 13, height: 1.5,
              fontStyle: FontStyle.italic)),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B), shape: BoxShape.circle),
                child: const Center(child: Text('⭐', style: TextStyle(fontSize: 14)))),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(
                color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w700)),
              const Text(' · ', style: TextStyle(color: Colors.white24)),
              Text(city, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.items.length, (i) => GestureDetector(
          onTap: () => setState(() => _idx = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _idx ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _idx ? const Color(0xFFF59E0B) : Colors.white24,
              borderRadius: BorderRadius.circular(3))))),
      ),
    ]);
  }
}

// ─── CTA PAYWALL ──────────────────────────────────────────────────────────────
class _PaywallCTA extends StatelessWidget {
  final String selectedPlan;
  final int price;
  final VoidCallback onTap;
  const _PaywallCTA({required this.selectedPlan, required this.price, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isXbet = selectedPlan == 'xbet';
    return GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); onTap(); },
      child: Container(
        width: double.infinity, height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isXbet
              ? [const Color(0xFF4C1D95), const Color(0xFF7C3AED)]
              : [const Color(0xFFB45309), const Color(0xFFF59E0B)],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: (isXbet ? const Color(0xFF7C3AED) : const Color(0xFFF59E0B))
              .withValues(alpha: 0.4),
            blurRadius: 20, offset: const Offset(0, 6))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            isXbet ? 'Activer avec Code 1xBet' : 'Passer au mensuel',
            style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
        ]),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
      .shimmer(duration: 2200.ms, color: Colors.white10, delay: 1200.ms);
  }
}

// ─── FOND GEOMETRIQUE ─────────────────────────────────────────────────────────
class _StadiumBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0A0E1A), Color(0xFF111827), Color(0xFF0D1117)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final glowOrange = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFF59E0B).withValues(alpha: 0.18), Colors.transparent,
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.1, size.height * 0.08), radius: size.width * 0.55));
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.08), size.width * 0.55, glowOrange);

    final glowPurple = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF7C3AED).withValues(alpha: 0.12), Colors.transparent,
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.9, size.height * 0.3), radius: size.width * 0.5));
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.3), size.width * 0.5, glowPurple);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.12),
        width: size.width * 1.4, height: size.width * 0.8),
      0, 3.14, false, linePaint);
    for (int i = 1; i <= 4; i++) {
      canvas.drawLine(
        Offset(size.width * i / 5, 0),
        Offset(size.width * i / 5, size.height * 0.25), linePaint);
    }
  }

  @override bool shouldRepaint(_) => false;
}
