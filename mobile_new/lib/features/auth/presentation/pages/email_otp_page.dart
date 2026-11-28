import 'package:pronowin/l10n/app_strings.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/apres_connexion.dart';
import '../providers/auth_provider.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../core/services/analyse_usage.dart';
import '../../../../shared/utils/messages.dart';
import 'email_auth_page.dart' show HaloMarque, largeurConnexion;

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/auth/email';

/// La saisie du code reçu par e-mail. Refaite le 20 novembre 2026 avec
/// l'écran de connexion : même halo, même largeur sur iPad, l'adresse
/// modifiable, et ce qu'on fait quand rien n'arrive (les codes tombent
/// parfois dans les courriers indésirables de Gmail).
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
    // Libéré ici seulement : le champ du code ne le libère plus lui-même
    // (`autoDisposeControllers: false`). Les deux le faisaient, et quitter
    // l'écran levait « TextEditingController used after being disposed ».
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
    _otpController.clear();
    setState(() => _otp = '');
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

  /// Retour à la saisie de l'adresse — une faute de frappe se corrige là.
  void _modifierAdresse() {
    ref.read(authProvider.notifier).reset();
    retourOuAller(context, repli: _repli);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        apresConnexionReussie(ref);
        AnalyseUsage.connexion(methode: 'email', nouveauCompte: widget.isNewUser);
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
        afficherMessage(context, state.message, type: TypeMessage.erreur);
      }
    });

    final masked = _maskEmail(widget.email);
    final minutes = _resendSeconds ~/ 60, secondes = _resendSeconds % 60;

    return Scaffold(
      backgroundColor: context.cl.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        const HaloMarque(),
        SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: tr(context, "Retour"),
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.cl.textS),
                onPressed: _modifierAdresse,
              ),
            ),

            Expanded(
              child: LayoutBuilder(builder: (context, contraintes) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: contraintes.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: largeurConnexion),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: AppColors.degradeMarque,
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

                          const SizedBox(height: 22),

                          Text(
                            widget.isNewUser ? tr(context, "Bienvenue !") : tr(context, "Content de te revoir !"),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.cl.textP,
                              fontSize: 22, fontWeight: FontWeight.w700,
                              letterSpacing: -0.4),
                          ).animate().fadeIn(duration: 400.ms, delay: 80.ms),

                          const SizedBox(height: 8),

                          Text.rich(
                            textAlign: TextAlign.center,
                            TextSpan(
                              style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.5),
                              children: [
                                TextSpan(text: tr(context, "Saisis le code à 6 chiffres envoyé à ")),
                                TextSpan(text: masked,
                                  style: TextStyle(color: context.cl.textP, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 120.ms),

                          TextButton(
                            key: const Key('otp-modifier-adresse'),
                            onPressed: _modifierAdresse,
                            child: Text(tr(context, "Modifier l'adresse"),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),

                          const SizedBox(height: 14),

                          // Six cases qui tiennent sur un petit écran comme
                          // sur iPad, sans dépasser 52 points chacune.
                          LayoutBuilder(builder: (context, c) {
                            final largeur = math.min(52.0, (c.maxWidth - 5 * 8) / 6);
                            return PinCodeTextField(
                              appContext: context,
                              length: 6,
                              controller: _otpController,
                              autoDisposeControllers: false,
                              autoFocus: true,
                              onChanged: (v) => setState(() => _otp = v),
                              onCompleted: (_) => _verify(),
                              keyboardType: TextInputType.number,
                              animationType: AnimationType.fade,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              pinTheme: PinTheme(
                                shape: PinCodeFieldShape.box,
                                borderRadius: BorderRadius.circular(14),
                                fieldHeight: largeur * 1.18,
                                fieldWidth: largeur,
                                borderWidth: 1,
                                activeFillColor: context.cl.surface,
                                inactiveFillColor: context.cl.surface,
                                selectedFillColor: context.cl.surface,
                                activeColor: AppColors.primary,
                                inactiveColor: context.cl.borderS,
                                selectedColor: AppColors.primary,
                              ),
                              enableActiveFill: true,
                              textStyle: TextStyle(
                                color: context.cl.textP,
                                fontSize: 22, fontWeight: FontWeight.w700),
                            );
                          }).animate().fadeIn(duration: 400.ms, delay: 160.ms),

                          const SizedBox(height: 6),

                          SizedBox(
                            width: double.infinity,
                            child: PwButton(
                              label: tr(context, "Vérifier"),
                              isLoading: authState is AuthLoading,
                              onPressed: _otp.length == 6 ? _verify : null,
                            ),
                          ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

                          const SizedBox(height: 14),

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _resendSeconds > 0
                              ? Padding(
                                  key: const ValueKey('timer'),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    tr(context, "Renvoyer le code dans {arg0}",
                                      ['$minutes:${secondes.toString().padLeft(2, '0')}']),
                                    style: TextStyle(color: context.cl.textS, fontSize: 13,
                                      fontFeatures: const [FontFeature.tabularFigures()])),
                                )
                              : TextButton.icon(
                                  key: const ValueKey('resend'),
                                  onPressed: _resend,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: Text(tr(context, "Renvoyer le code")),
                                ),
                          ),

                          const SizedBox(height: 10),

                          // Le cas le plus fréquent quand rien n'arrive.
                          Container(
                            key: const Key('otp-conseil-spam'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.cl.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.cl.borderS),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: context.cl.textS),
                              const SizedBox(width: 10),
                              Expanded(child: Text(
                                tr(context, "Rien reçu ? Regarde dans les courriers indésirables (spam) ou les promotions, puis vérifie l'adresse."),
                                style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.45))),
                            ]),
                          ).animate().fadeIn(duration: 400.ms, delay: 240.ms),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
            ),
          ]),
        ),
      ]),
    );
  }

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final visible = email.substring(0, 2);
    return '$visible${'*' * (at - 2)}${email.substring(at)}';
  }
}
