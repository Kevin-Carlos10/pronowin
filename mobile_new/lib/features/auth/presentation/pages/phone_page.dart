import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/auth_provider.dart';

class PhonePage extends ConsumerStatefulWidget {
  const PhonePage({super.key});

  @override
  ConsumerState<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends ConsumerState<PhonePage>
    with TickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _countryCode = '+226';
  int    _tab         = 0; // 0 = Téléphone, 1 = Email

  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  final List<Map<String, String>> _countries = [
    {'code': '+226', 'flag': '🇧🇫', 'name': 'Burkina Faso'},
    {'code': '+225', 'flag': '🇨🇮', 'name': "Côte d'Ivoire"},
    {'code': '+221', 'flag': '🇸🇳', 'name': 'Sénégal'},
    {'code': '+223', 'flag': '🇲🇱', 'name': 'Mali'},
    {'code': '+224', 'flag': '🇬🇳', 'name': 'Guinée'},
    {'code': '+33',  'flag': '🇫🇷', 'name': 'France'},
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _bgAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut),
    );
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bgCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_tab == 0) {
      final fullNumber = '$_countryCode${_phoneCtrl.text.trim()}';
      ref.read(authProvider.notifier).quickRegister(phoneNumber: fullNumber);
    } else {
      ref.read(authProvider.notifier).quickRegister(email: _emailCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        // Le router GoRouter redirigera automatiquement vers /home
      } else if (state is AuthError) {
        HapticFeedback.mediumImpact();
        _shakeCtrl.forward(from: 0);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    });

    final country = _countries.firstWhere((c) => c['code'] == _countryCode);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ─── FOND ANIMÉ ────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (_, _) => Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    -0.5 + _bgAnim.value * 0.4,
                    -0.8 + _bgAnim.value * 0.2,
                  ),
                  radius: 1.2,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15 + _bgAnim.value * 0.05),
                    context.cl.bg,
                    context.cl.surfaceD,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ─── CONTENU ────────────────────────────────────────────────────
          SafeArea(
            child: AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(
                  _shakeCtrl.isAnimating
                    ? 8 * (0.5 - (_shakeAnim.value % 0.25) / 0.25).abs() * (1 - _shakeAnim.value)
                    : 0,
                  0,
                ),
                child: child,
              ),
              child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 36),

                    // Logo
                    _LogoBrand()
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
                          duration: 500.ms, curve: Curves.easeOutBack)
                      .slideY(begin: -0.08, end: 0, duration: 500.ms,
                          curve: Curves.easeOutCubic),

                    const SizedBox(height: 28),

                    // Étapes
                    _StepIndicator(current: 1, total: 2)
                      .animate().fadeIn(duration: 400.ms, delay: 80.ms),

                    const SizedBox(height: 20),

                    // ─── TITRE ─────────────────────────────────────────────
                    Text(
                      'Bienvenue sur PronoWin',
                      style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 100.ms),
                    const SizedBox(height: 6),
                    Text(
                      'Entre ton numéro ou email pour commencer instantanément.',
                      style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
                    ).animate().fadeIn(duration: 500.ms, delay: 140.ms),

                    const SizedBox(height: 24),

                    // ─── TAB SWITCHER ──────────────────────────────────────
                    _AuthTabSwitcher(
                      selected: _tab,
                      onChanged: (i) => setState(() { _tab = i; _formKey.currentState?.reset(); }),
                    ).animate().fadeIn(duration: 400.ms, delay: 160.ms),

                    const SizedBox(height: 20),

                    // ─── CONTENU SELON TAB ─────────────────────────────────
                    if (_tab == 0) ...[
                      _FieldLabel('Pays').animate().fadeIn(duration: 400.ms, delay: 180.ms),
                      const SizedBox(height: 8),
                      _CountrySelector(
                        country: country,
                        onTap: () => _showCountryPicker(context),
                      ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                      const SizedBox(height: 16),
                      _FieldLabel('Numéro de téléphone').animate().fadeIn(duration: 400.ms, delay: 220.ms),
                      const SizedBox(height: 8),
                      Row(children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: Tween<double>(begin: 0.85, end: 1.0)
                              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
                            child: FadeTransition(opacity: anim, child: child)),
                          child: _CountryCodeBadge(key: ValueKey(_countryCode), code: _countryCode),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: TextStyle(color: context.cl.textP, fontSize: 15),
                            decoration: const InputDecoration(hintText: 'XX XX XX XX'),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Numéro requis';
                              if (v.length < 7) return 'Numéro trop court';
                              return null;
                            },
                          ),
                        ),
                      ]).animate().fadeIn(duration: 400.ms, delay: 240.ms),
                    ] else ...[
                      _FieldLabel('Adresse email').animate().fadeIn(duration: 300.ms, delay: 180.ms),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: context.cl.textP, fontSize: 15),
                        decoration: const InputDecoration(hintText: 'exemple@email.com'),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Email requis';
                          if (!v.contains('@')) return 'Email invalide';
                          return null;
                        },
                      ).animate().fadeIn(duration: 300.ms, delay: 180.ms),
                    ],

                    const SizedBox(height: 12),

                    // Bannière "pas de vérification"
                    _NoBotherBanner().animate().fadeIn(duration: 400.ms, delay: 260.ms),

                    const SizedBox(height: 28),

                    // Bouton
                    PwButton(
                      label: 'Commencer maintenant',
                      isLoading: authState is AuthLoading,
                      onPressed: _submit,
                      icon: Icons.arrow_forward_rounded,
                    ).animate().fadeIn(duration: 400.ms, delay: 300.ms)
                      .slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 14),

                    Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(color: context.cl.textM, fontSize: 11),
                          children: [
                            const TextSpan(text: 'En continuant, vous acceptez nos '),
                            TextSpan(
                              text: 'conditions d\'utilisation',
                              style: const TextStyle(
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => context.push('/parametres/cgu')),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),           // SingleChildScrollView
          ),             // AnimatedBuilder
        ),               // SafeArea
        ],
      ),
    );
  }

  void _showCountryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: context.cl.borderS,
              borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.language_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text('Choisir un pays',
                  style: TextStyle(
                      color: context.cl.textP,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 12),
          ..._countries.map((c) => InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _countryCode = c['code']!);
              Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              child: Row(children: [
                Text(c['flag']!, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(c['name']!,
                      style: TextStyle(
                          color: context.cl.textP, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c['code']!,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── LOGO ─────────────────────────────────────────────────────────────────────
class _LogoBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.emoji_events_rounded,
            color: Colors.white, size: 26),
      ),
      const SizedBox(width: 12),
      RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          children: [
            TextSpan(
                text: 'Prono',
                style: TextStyle(color: context.cl.textP)),
            const TextSpan(
                text: 'Win',
                style: TextStyle(color: AppColors.primaryLight)),
          ],
        ),
      ),
    ],
  );
}

// ─── LABEL CHAMP ──────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
        color: context.cl.textS,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5),
  );
}

// ─── SÉLECTEUR PAYS ───────────────────────────────────────────────────────────
class _CountrySelector extends StatelessWidget {
  final Map<String, String> country;
  final VoidCallback onTap;
  const _CountrySelector({required this.country, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.cl.surfaceD,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cl.borderS, width: 0.5),
      ),
      child: Row(children: [
        Text(country['flag']!, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${country['name']} (${country['code']})',
            style: TextStyle(
                color: context.cl.textP, fontSize: 14),
          ),
        ),
        Icon(Icons.keyboard_arrow_down_rounded,
            color: context.cl.textM, size: 20),
      ]),
    ),
  );
}

// ─── BADGE CODE PAYS ──────────────────────────────────────────────────────────
class _CountryCodeBadge extends StatelessWidget {
  final String code;
  const _CountryCodeBadge({super.key, required this.code});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1),
    ),
    child: Text(
      code,
      style: const TextStyle(
          color: AppColors.primary,
          fontSize: 14,
          fontWeight: FontWeight.w700),
    ),
  );
}

// ─── BANNIÈRE PAS DE VÉRIFICATION ────────────────────────────────────────────
class _NoBotherBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.2), width: 0.5),
    ),
    child: Row(children: [
      const Icon(Icons.flash_on_rounded, color: AppColors.success, size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'Aucun code de vérification — accès instantané à l\'application.',
          style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4),
        ),
      ),
    ]),
  );
}


// ─── TAB SWITCHER AUTH ────────────────────────────────────────────────────────
class _AuthTabSwitcher extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _AuthTabSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.cl.surfaceD,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.borderS, width: 0.5),
    ),
    child: Row(children: [
      _Tab(label: 'WhatsApp', icon: Icons.chat_outlined,  selected: selected == 0, onTap: () => onChanged(0)),
      const SizedBox(width: 4),
      _Tab(label: 'Email',     icon: Icons.email_outlined, selected: selected == 1, onTap: () => onChanged(1)),
    ]),
  );
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
          ] : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? Colors.white : context.cl.textM),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: selected ? Colors.white : context.cl.textM,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          )),
        ]),
      ),
    ),
  );
}

// ─── INDICATEUR D'ÉTAPES ──────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(total, (i) {
      final active = i < current;
      final isCurrent = i == current - 1;
      return Expanded(
        child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
          decoration: BoxDecoration(
            color: active
              ? (isCurrent ? AppColors.primary : AppColors.primary.withValues(alpha: 0.5))
              : context.cl.borderS,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }),
  );
}
