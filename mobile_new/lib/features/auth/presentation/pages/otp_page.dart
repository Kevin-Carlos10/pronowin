import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/auth_provider.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../compte/presentation/providers/compte_provider.dart';


class OtpPage extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpPage({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage>
    with TickerProviderStateMixin {
  final _otpController = TextEditingController();
  bool  _disposed      = false;
  int _resendSeconds = 60;
  Timer? _timer;
  String _otp = '';

  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;
  late AnimationController _successCtrl;
  late Animation<double> _successAnim;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _bgCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _bgAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut));
    _successCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _successAnim = CurvedAnimation(parent: _successCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _otpController.dispose();
    _bgCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _resendSeconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_resendSeconds > 0) {
        if (!_disposed) setState(() => _resendSeconds--);
      } else {
        _timer?.cancel();
      }
    });
  }

  void _resend() {
    ref.read(authProvider.notifier).sendOtp(widget.phoneNumber);
    _startTimer();
  }

  void _verify() {
    if (_otp.length == 6) {
      ref.read(authProvider.notifier).verifyOtp(
            phoneNumber: widget.phoneNumber,
            otp: _otp,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        // Invalider tous les providers mis en cache pour l'ancien compte
        ref.invalidate(isLoggedInProvider);
        ref.invalidate(bankrollProvider);
        ref.invalidate(bankrollStatsProvider);
        ref.invalidate(profileProvider);
        ref.invalidate(userStatsProvider);
        if (state.user.acceptedTermsAt == null) {
          context.go('/auth/terms');
        } else {
          context.go('/home');
        }
      } else if (state is TermsAccepted) {
        ref.invalidate(isLoggedInProvider);
        ref.invalidate(bankrollProvider);
        ref.invalidate(bankrollStatsProvider);
        ref.invalidate(profileProvider);
        ref.invalidate(userStatsProvider);
        context.go('/home');
      } else if (state is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    });

    final masked = widget.phoneNumber.replaceRange(
      widget.phoneNumber.length - 4,
      widget.phoneNumber.length,
      '****',
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ─── FOND ANIMÉ ───────────────────────────────────────────────
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (_, _) => Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.3 + _bgAnim.value * 0.3, -0.6),
                  radius: 1.1,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10 + _bgAnim.value * 0.05),
                    context.cl.bg,
                    context.cl.surfaceD,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ─── CONTENU ─────────────────────────────────────────────────
          SafeArea(
            child: Column(children: [
              // AppBar manuel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: context.cl.textP),
                    onPressed: () {
                      ref.read(authProvider.notifier).reset();
                      context.pop();
                    },
                  ),
                ]),
              ),

              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Icône animée
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 16, offset: const Offset(0, 6))]),
                        child: const Icon(Icons.chat_rounded,
                          color: Colors.white, size: 32),
                      ).animate().fadeIn(duration: 500.ms)
                       .scale(begin: const Offset(0.7, 0.7), duration: 400.ms,
                           curve: Curves.easeOutBack),

                      const SizedBox(height: 20),

                      // Étapes
                      _StepIndicator(current: 2, total: 2)
                        .animate().fadeIn(duration: 400.ms, delay: 80.ms),

                      const SizedBox(height: 20),

                      Text('Vérification WhatsApp',
                        style: TextStyle(
                          color: context.cl.textP,
                          fontSize: 28, fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                      ).animate().fadeIn(duration: 400.ms, delay: 100.ms)
                       .slideX(begin: -0.1, end: 0),

                      const SizedBox(height: 8),

                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: context.cl.textS, fontSize: 14, height: 1.5),
                          children: [
                            const TextSpan(text: 'Code WhatsApp envoyé au '),
                            TextSpan(text: masked,
                              style: TextStyle(
                                color: context.cl.textP,
                                fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

                      const SizedBox(height: 36),

                      PinCodeTextField(
                        appContext: context,
                        length: 6,
                        controller: _otpController,
                        onChanged: (v) {
                          setState(() => _otp = v);
                          if (v.length == 6) {
                            HapticFeedback.lightImpact();
                            _successCtrl.forward(from: 0);
                          } else {
                            _successCtrl.reverse();
                          }
                        },
                        onCompleted: (_) => _verify(),
                        keyboardType: TextInputType.number,
                        animationType: AnimationType.scale,
                        pinTheme: PinTheme(
                          shape: PinCodeFieldShape.box,
                          borderRadius: BorderRadius.circular(14),
                          fieldHeight: 58,
                          fieldWidth: 46,
                          activeFillColor: context.cl.surface,
                          inactiveFillColor: context.cl.surfaceD,
                          selectedFillColor: context.cl.surface,
                          activeColor: AppColors.primary,
                          inactiveColor: context.cl.borderS,
                          selectedColor: AppColors.primary,
                        ),
                        enableActiveFill: true,
                        textStyle: TextStyle(
                          color: context.cl.textP,
                          fontSize: 22, fontWeight: FontWeight.w700),
                      ).animate().fadeIn(duration: 400.ms, delay: 200.ms)
                       .slideY(begin: 0.1, end: 0),

                      // ── Indicateur succès (6/6 chiffres) ─────────────────
                      ScaleTransition(
                        scale: _successAnim,
                        child: AnimatedOpacity(
                          opacity: _otp.length == 6 ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.success.withValues(alpha: 0.3),
                                  width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.success, size: 16),
                                const SizedBox(width: 8),
                                Text('Code complet — appuyez sur Vérifier',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.88, end: 1.0)
                                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
                              child: child)),
                          child: _resendSeconds > 0
                            ? Container(
                                key: const ValueKey('timer'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: context.cl.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: context.cl.border, width: 0.5)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.timer_outlined,
                                    size: 14, color: context.cl.textM),
                                  const SizedBox(width: 6),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                                    child: Text('Renvoyer dans ${_resendSeconds}s',
                                      key: ValueKey(_resendSeconds),
                                      style: TextStyle(color: context.cl.textM, fontSize: 13)),
                                  ),
                                ]),
                              )
                            : TextButton.icon(
                                key: const ValueKey('resend'),
                                onPressed: _resend,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Renvoyer le code'),
                              ),
                        ),
                      ).animate().fadeIn(duration: 300.ms, delay: 280.ms),

                      const SizedBox(height: 32),

                      PwButton(
                        label: 'Vérifier le code',
                        isLoading: authState is AuthLoading,
                        onPressed: _otp.length == 6 ? _verify : null,
                        icon: Icons.check_circle_outline_rounded,
                      ).animate().fadeIn(duration: 350.ms, delay: 350.ms)
                       .slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
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
