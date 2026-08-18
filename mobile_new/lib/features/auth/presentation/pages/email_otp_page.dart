import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/auth_provider.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../compte/presentation/providers/compte_provider.dart';
import '../../../notifications/presentation/providers/fcm_service.dart';

class EmailOtpPage extends ConsumerStatefulWidget {
  final String email;
  final bool   isNewUser;
  final String? from;
  const EmailOtpPage({
    super.key,
    required this.email,
    this.isNewUser = false,
    this.from,
  });

  @override
  ConsumerState<EmailOtpPage> createState() => _EmailOtpPageState();
}

class _EmailOtpPageState extends ConsumerState<EmailOtpPage> {
  final _otpController = TextEditingController();
  bool  _disposed      = false;
  int _resendSeconds = 60;
  Timer? _timer;
  String _otp = '';

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _otpController.dispose();
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
    ref.read(authProvider.notifier).sendEmailOtp(widget.email);
    _startTimer();
  }

  void _verify() {
    // Garde contre un double appel (ex: onCompleted du champ PIN qui se
    // déclenche pendant qu'un appui sur "Vérifier" est déjà en cours).
    if (_otp.length == 6 && ref.read(authProvider) is! AuthLoading) {
      ref.read(authProvider.notifier).verifyEmailOtp(
            email: widget.email,
            otp:   _otp,
          );
    }
  }

  void _invalidateUserProviders() {
    ref.invalidate(isLoggedInProvider);
    ref.invalidate(bankrollProvider);
    ref.invalidate(bankrollStatsProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(userStatsProvider);
    // Rattacher le token FCM déjà obtenu en mode invité au compte qui vient
    // de se connecter (fire-and-forget, non bloquant).
    FCMService.registerCurrentToken(ref);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        _invalidateUserProviders();
        // Le code validé, l'utilisateur est chez lui — point final.
        //
        // Il y avait ici deux détours obligatoires : un écran de CGU, alors
        // que le consentement est déjà recueilli sur l'écran précédent, puis
        // un formulaire d'identité sans bouton retour ni « plus tard ». Ces
        // champs ne servent qu'au paiement Mobile Money du Premium
        // (`requireProfileComplete` ne garde que deux routes) : ils sont
        // maintenant demandés là-bas, au moment où ils ont un sens.
        context.go(widget.from ?? '/home');
      } else if (state is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    });

    final masked = _maskEmail(widget.email);

    return Scaffold(
      backgroundColor: context.cl.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.cl.textS),
              onPressed: () {
                ref.read(authProvider.notifier).reset();
                context.pop();
              },
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 18, offset: const Offset(0, 8))]),
                      child: const Icon(Icons.mark_email_read_rounded,
                        color: Colors.white, size: 30),
                    ).animate().fadeIn(duration: 400.ms)
                     .scale(begin: const Offset(0.85, 0.85), duration: 400.ms,
                         curve: Curves.easeOutBack),

                    const SizedBox(height: 24),

                    Text(
                      widget.isNewUser ? 'Bienvenue !' : 'Content de te revoir !',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.cl.textP,
                        fontSize: 22, fontWeight: FontWeight.w800,
                        letterSpacing: -0.4),
                    ).animate().fadeIn(duration: 400.ms, delay: 80.ms),

                    const SizedBox(height: 8),

                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(color: context.cl.textS, fontSize: 13.5, height: 1.5),
                        children: [
                          TextSpan(text: widget.isNewUser
                            ? 'Code de vérification envoyé à '
                            : 'Code de connexion envoyé à '),
                          TextSpan(text: masked,
                            style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 120.ms),

                    const SizedBox(height: 32),

                    PinCodeTextField(
                      appContext: context,
                      length: 6,
                      controller: _otpController,
                      onChanged: (v) => setState(() => _otp = v),
                      onCompleted: (_) => _verify(),
                      keyboardType: TextInputType.number,
                      animationType: AnimationType.fade,
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(14),
                        fieldHeight: 54,
                        fieldWidth: 44,
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
                        fontSize: 20, fontWeight: FontWeight.w700),
                    ).animate().fadeIn(duration: 400.ms, delay: 160.ms),

                    const SizedBox(height: 20),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _resendSeconds > 0
                        ? Text('Renvoyer le code dans ${_resendSeconds}s',
                            key: const ValueKey('timer'),
                            style: TextStyle(color: context.cl.textM, fontSize: 12.5))
                        : TextButton(
                            key: const ValueKey('resend'),
                            onPressed: _resend,
                            child: const Text('Renvoyer le code'),
                          ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: PwButton(
                        label: 'Vérifier',
                        isLoading: authState is AuthLoading,
                        onPressed: _otp.length == 6 ? _verify : null,
                      ),
                    ).animate().fadeIn(duration: 350.ms, delay: 200.ms),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final visible = email.substring(0, 2);
    return '$visible${'*' * (at - 2)}${email.substring(at)}';
  }
}
