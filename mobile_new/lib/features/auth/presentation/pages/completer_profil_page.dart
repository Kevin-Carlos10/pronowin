import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/auth_provider.dart';

/// Page de complétion de profil avant l'accès au premium.
/// Étape 1 : Infos personnelles (nom, prénom, date de naissance)
/// Étape 2 : Vérification contact (WhatsApp OTP ou Email OTP)
class CompleterProfilPage extends ConsumerStatefulWidget {
  const CompleterProfilPage({super.key});

  @override
  ConsumerState<CompleterProfilPage> createState() => _CompleterProfilPageState();
}

class _CompleterProfilPageState extends ConsumerState<CompleterProfilPage> {
  int _step = 0; // 0 = infos perso, 1 = vérification contact

  // Étape 1
  final _formKey1     = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  DateTime? _birthDate;
  bool _savingInfo = false;

  // Étape 2
  final _formKey2   = GlobalKey<FormState>();
  final _contactCtrl = TextEditingController();
  final _otpCtrl     = TextEditingController();
  int  _verifTab    = 0; // 0 = WhatsApp, 1 = Email
  bool _otpSent     = false;
  bool _verifLoading = false;
  String _countryCode = '+226';

  final List<Map<String, String>> _countries = [
    {'code': '+226', 'flag': '🇧🇫', 'name': 'Burkina Faso'},
    {'code': '+225', 'flag': '🇨🇮', 'name': "Côte d'Ivoire"},
    {'code': '+221', 'flag': '🇸🇳', 'name': 'Sénégal'},
    {'code': '+223', 'flag': '🇲🇱', 'name': 'Mali'},
    {'code': '+224', 'flag': '🇬🇳', 'name': 'Guinée'},
    {'code': '+33',  'flag': '🇫🇷', 'name': 'France'},
  ];

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _contactCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ─── ÉTAPE 1 : sauvegarder les infos perso via PATCH /profile ─────────────
  Future<void> _savePersonalInfo() async {
    if (!(_formKey1.currentState?.validate() ?? false)) return;
    setState(() => _savingInfo = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/profile', data: {
        'first_name': _firstNameCtrl.text.trim(),
        'last_name':  _lastNameCtrl.text.trim(),
        'birth_date': _birthDate!.toIso8601String().substring(0, 10),
      });
      setState(() { _step = 1; _savingInfo = false; });
    } catch (e) {
      setState(() => _savingInfo = false);
      if (mounted) {
        final msg = e is DioException
            ? (e.response?.data?['message'] ?? 'Erreur réseau')
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── ÉTAPE 2 : envoyer OTP ─────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!(_formKey2.currentState?.validate() ?? false)) return;
    setState(() => _verifLoading = true);
    try {
      if (_verifTab == 0) {
        final phone = '$_countryCode${_contactCtrl.text.trim()}';
        await ref.read(authProvider.notifier).sendOtp(phone);
      } else {
        await ref.read(authProvider.notifier).sendEmailOtp(_contactCtrl.text.trim());
      }
      setState(() { _otpSent = true; _verifLoading = false; });
    } catch (e) {
      setState(() => _verifLoading = false);
    }
  }

  // ─── ÉTAPE 2 : vérifier OTP ────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.length != 6) return;
    setState(() => _verifLoading = true);
    try {
      if (_verifTab == 0) {
        final phone = '$_countryCode${_contactCtrl.text.trim()}';
        await ref.read(authProvider.notifier).verifyOtp(
          phoneNumber: phone, otp: _otpCtrl.text.trim());
      } else {
        await ref.read(authProvider.notifier).verifyEmailOtp(
          email: _contactCtrl.text.trim(), otp: _otpCtrl.text.trim());
      }
      // Succès → le listener redirigera
    } catch (e) {
      setState(() => _verifLoading = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 18),
      helpText: 'Date de naissance',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: context.cl.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated && state.user.isProfileComplete) {
        context.go('/compte/activer-premium');
      } else if (state is OtpSent) {
        setState(() { _otpSent = true; _verifLoading = false; });
      } else if (state is AuthError) {
        setState(() => _verifLoading = false);
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    });

    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cl.textP, size: 18),
          onPressed: () {
            if (_step == 1 && !_otpSent) {
              setState(() => _step = 0);
            } else if (_step == 1 && _otpSent) {
              setState(() => _otpSent = false);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _step == 0 ? 'Informations personnelles' : 'Vérification du compte',
          style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(width: 4),
              Expanded(child: Container(
                decoration: BoxDecoration(
                  color: _step >= 1 ? AppColors.primary : context.cl.borderS,
                  borderRadius: BorderRadius.circular(2)),
              )),
            ]),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: _step == 0
              ? _buildStep1(key: const ValueKey(0))
              : _buildStep2(key: const ValueKey(1)),
        ),
      ),
    );
  }

  // ─── ÉTAPE 1 ───────────────────────────────────────────────────────────────
  Widget _buildStep1({Key? key}) => Form(
    key: _formKey1,
    child: Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.person_outline_rounded,
          title: 'Qui es-tu ?',
          subtitle: 'Ces informations sont nécessaires pour accéder au premium.',
        ).animate().fadeIn(duration: 400.ms),

        const SizedBox(height: 24),

        _Label('Prénom'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _firstNameCtrl,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: context.cl.textP, fontSize: 15),
          decoration: const InputDecoration(hintText: 'Ton prénom'),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Prénom requis';
            if (v.trim().length < 2) return 'Minimum 2 caractères';
            return null;
          },
        ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

        const SizedBox(height: 16),

        _Label('Nom de famille'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _lastNameCtrl,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: context.cl.textP, fontSize: 15),
          decoration: const InputDecoration(hintText: 'Ton nom'),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Nom requis';
            if (v.trim().length < 2) return 'Minimum 2 caractères';
            return null;
          },
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

        const SizedBox(height: 16),

        _Label('Date de naissance'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickBirthDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.cl.surfaceD,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _birthDate == null ? context.cl.borderS : AppColors.primary,
                width: _birthDate == null ? 0.5 : 1.2,
              ),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded,
                  color: _birthDate == null ? context.cl.textM : AppColors.primary, size: 18),
              const SizedBox(width: 12),
              Text(
                _birthDate == null
                    ? 'Sélectionner la date'
                    : '${_birthDate!.day.toString().padLeft(2, '0')}/'
                      '${_birthDate!.month.toString().padLeft(2, '0')}/'
                      '${_birthDate!.year}',
                style: TextStyle(
                  color: _birthDate == null ? context.cl.textM : context.cl.textP,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Icon(Icons.keyboard_arrow_down_rounded, color: context.cl.textM, size: 20),
            ]),
          ),
        ).animate().fadeIn(duration: 300.ms, delay: 140.ms),

        if (_birthDate == null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Tu dois avoir au moins 18 ans.',
              style: TextStyle(color: context.cl.textM, fontSize: 11),
            ),
          ),

        const SizedBox(height: 36),

        PwButton(
          label: 'Continuer',
          isLoading: _savingInfo,
          onPressed: _birthDate == null
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sélectionne ta date de naissance.')))
              : _savePersonalInfo,
          icon: Icons.arrow_forward_rounded,
        ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
      ],
    ),
  );

  // ─── ÉTAPE 2 ───────────────────────────────────────────────────────────────
  Widget _buildStep2({Key? key}) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(
        icon: Icons.verified_user_outlined,
        title: 'Vérifie ton identité',
        subtitle: 'Un code sera envoyé pour confirmer que c\'est bien toi.',
      ).animate().fadeIn(duration: 400.ms),

      const SizedBox(height: 24),

      if (!_otpSent) ...[
        // Tab WhatsApp / Email
        _VerifTabSwitcher(
          selected: _verifTab,
          onChanged: (i) => setState(() { _verifTab = i; _contactCtrl.clear(); }),
        ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

        const SizedBox(height: 16),

        Form(
          key: _formKey2,
          child: _verifTab == 0
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Label('Pays'),
                  const SizedBox(height: 8),
                  _CountrySelectorCompact(
                    countryCode: _countryCode,
                    countries: _countries,
                    onSelect: (c) => setState(() => _countryCode = c),
                  ),
                  const SizedBox(height: 12),
                  _Label('Numéro WhatsApp'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _contactCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: context.cl.textP, fontSize: 15),
                    decoration: const InputDecoration(hintText: 'XX XX XX XX'),
                    validator: (v) => (v == null || v.length < 7) ? 'Numéro invalide' : null,
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Label('Adresse email'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _contactCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: context.cl.textP, fontSize: 15),
                    decoration: const InputDecoration(hintText: 'exemple@email.com'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
                  ),
                ]),
        ).animate().fadeIn(duration: 300.ms, delay: 80.ms),

        const SizedBox(height: 28),

        PwButton(
          label: _verifTab == 0 ? 'Envoyer le code WhatsApp' : 'Envoyer le code par email',
          isLoading: _verifLoading,
          onPressed: _sendOtp,
          icon: _verifTab == 0 ? Icons.chat_outlined : Icons.email_outlined,
        ).animate().fadeIn(duration: 400.ms, delay: 140.ms),
      ] else ...[
        // Saisie du code OTP
        _OtpCodeStep(
          contact: _verifTab == 0
              ? '$_countryCode${_contactCtrl.text.trim()}'
              : _contactCtrl.text.trim(),
          isPhone: _verifTab == 0,
          otpCtrl: _otpCtrl,
          isLoading: _verifLoading,
          onVerify: _verifyOtp,
          onResend: () => setState(() => _otpSent = false),
        ).animate().fadeIn(duration: 400.ms),
      ],
    ],
  );
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.03)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 24),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
      ])),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
}

class _VerifTabSwitcher extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _VerifTabSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.borderS, width: 0.5),
    ),
    child: Row(children: [
      _VTab(label: 'WhatsApp', icon: Icons.chat_outlined,  selected: selected == 0, onTap: () => onChanged(0)),
      const SizedBox(width: 4),
      _VTab(label: 'Email',     icon: Icons.email_outlined, selected: selected == 1, onTap: () => onChanged(1)),
    ]),
  );
}

class _VTab extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _VTab({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: selected ? Colors.white : context.cl.textM),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: selected ? Colors.white : context.cl.textM, fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    ),
  );
}

class _CountrySelectorCompact extends StatelessWidget {
  final String countryCode;
  final List<Map<String, String>> countries;
  final ValueChanged<String> onSelect;
  const _CountrySelectorCompact({required this.countryCode, required this.countries, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = countries.firstWhere((x) => x['code'] == countryCode);
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: context.cl.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(color: context.cl.borderS, borderRadius: BorderRadius.circular(2))),
          ...countries.map((c) => InkWell(
            onTap: () { onSelect(c['code']!); Navigator.pop(context); },
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Text(c['flag']!, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 14),
                Expanded(child: Text(c['name']!, style: TextStyle(color: context.cl.textP, fontSize: 14))),
                Text(c['code']!, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          )),
          const SizedBox(height: 20),
        ]),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.cl.surfaceD,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.borderS, width: 0.5),
        ),
        child: Row(children: [
          Text(c['flag']!, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('${c['name']} (${c['code']})', style: TextStyle(color: context.cl.textP, fontSize: 13))),
          Icon(Icons.keyboard_arrow_down_rounded, color: context.cl.textM, size: 18),
        ]),
      ),
    );
  }
}

class _OtpCodeStep extends StatelessWidget {
  final String contact;
  final bool isPhone;
  final TextEditingController otpCtrl;
  final bool isLoading;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  const _OtpCodeStep({
    required this.contact, required this.isPhone,
    required this.otpCtrl, required this.isLoading,
    required this.onVerify, required this.onResend,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(isPhone ? Icons.chat_outlined : Icons.email_outlined, color: AppColors.info, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(
            'Code envoyé à $contact',
            style: TextStyle(color: context.cl.textS, fontSize: 13),
          )),
        ]),
      ),
      const SizedBox(height: 20),
      Text('Code à 6 chiffres',
        style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      TextFormField(
        controller: otpCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        style: TextStyle(color: context.cl.textP, fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(
          hintText: '------',
          counterText: '',
        ),
      ),
      const SizedBox(height: 28),
      PwButton(
        label: 'Vérifier le code',
        isLoading: isLoading,
        onPressed: onVerify,
        icon: Icons.verified_rounded,
      ),
      const SizedBox(height: 14),
      Center(
        child: TextButton.icon(
          onPressed: onResend,
          icon: Icon(Icons.refresh_rounded, size: 16, color: context.cl.textM),
          label: Text("Renvoyer le code", style: TextStyle(color: context.cl.textM, fontSize: 13)),
        ),
      ),
    ],
  );
}
