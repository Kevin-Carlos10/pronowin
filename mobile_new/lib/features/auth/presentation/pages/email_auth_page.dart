import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/auth_provider.dart';

/// Écran de connexion / inscription par email — accessible uniquement à la
/// demande (bouton "Se connecter" ou accès à une fonctionnalité réservée).
/// L'application elle-même reste consultable sans compte.
///
/// Style épuré (logo + bénéfices + un seul CTA), inspiré des écrans d'auth
/// des grosses apps sport (Sofascore, OneFootball) : peu de texte, une seule
/// action claire, pas de choix "connexion / inscription" à faire soi-même.
class EmailAuthPage extends ConsumerStatefulWidget {
  /// Route vers laquelle rediriger une fois connecté (fonctionnalité que
  /// l'invité tentait d'atteindre).
  final String? from;
  const EmailAuthPage({super.key, this.from});

  @override
  ConsumerState<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends ConsumerState<EmailAuthPage> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref.read(authProvider.notifier).sendEmailOtp(_emailCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is EmailOtpSent) {
        context.push('/auth/email/otp', extra: {
          'email':     state.email,
          'isNewUser': state.isNewUser,
          'from':      widget.from,
        });
      } else if (state is AuthError) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    });

    return Scaffold(
      backgroundColor: context.cl.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.close_rounded, color: context.cl.textS),
                onPressed: () => Navigator.of(context).canPop()
                  ? context.pop()
                  : context.go('/home'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.62,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _LogoMark()
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1),
                            duration: 400.ms, curve: Curves.easeOutBack),

                      const SizedBox(height: 24),

                      Text(
                        'Tout PronoWin en un compte',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.cl.textP,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 80.ms),

                      const SizedBox(height: 24),

                      // Les trois lignes partagent une colonne alignée à
                      // gauche : centrées individuellement, leurs pastilles se
                      // décalaient au gré de la longueur de chaque texte.
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BenefitRow(text: 'Suis tes pronostics et paris favoris'),
                          SizedBox(height: 12),
                          _BenefitRow(
                              text: 'Débloque le Premium et l\'analyse statistique'),
                          SizedBox(height: 12),
                          _BenefitRow(text: 'Gère ta bankroll et ton parrainage'),
                        ],
                      ),

                      const SizedBox(height: 32),

                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _emailCtrl,
                          autofocus: false,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          // Laisse le gestionnaire de mots de passe et la
                          // saisie automatique proposer l'adresse.
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          enableSuggestions: false,
                          onFieldSubmitted: (_) => _submit(),
                          style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(hintText: 'Adresse email'),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Email requis';
                            if (!v.contains('@')) return 'Email invalide';
                            return null;
                          },
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 140.ms),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: PwButton(
                          label: 'Continuer',
                          isLoading: authState is AuthLoading,
                          onPressed: _submit,
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 180.ms),

                      const SizedBox(height: 18),

                      // Séparateur
                      Row(children: [
                        Expanded(child: Divider(color: context.cl.border, height: 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('ou',
                              style: TextStyle(
                                  color: context.cl.textM, fontSize: 12)),
                        ),
                        Expanded(child: Divider(color: context.cl.border, height: 1)),
                      ]).animate().fadeIn(duration: 400.ms, delay: 210.ms),

                      const SizedBox(height: 18),

                      // Deux appuis au lieu de : saisir l'adresse, attendre le
                      // code, aller le chercher dans sa boîte mail, le ressaisir.
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: authState is AuthLoading
                              ? null
                              : () async {
                                  final ok = await ref
                                      .read(authProvider.notifier)
                                      .loginWithGoogle();
                                  if (!ok || !context.mounted) return;
                                },
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                          label: const Text('Continuer avec Google'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.cl.textP,
                            side: BorderSide(color: context.cl.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 240.ms),

                      const SizedBox(height: 18),

                      // Seul recueil de consentement depuis la suppression de
                      // l'écran de CGU : cette mention doit être lisible, pas
                      // décorative. `textM` donnait 2,5:1 sur ce fond, sous le
                      // seuil AA de 4,5:1 ; `textS` monte à ~6:1.
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(color: context.cl.textS, fontSize: 12.5, height: 1.45),
                          children: [
                            const TextSpan(text: 'En continuant, tu acceptes nos '),
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LOGO ─────────────────────────────────────────────────────────────────────
class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 64, height: 64,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 32),
  );
}

// ─── BÉNÉFICE (checkmark + texte) ─────────────────────────────────────────────
class _BenefitRow extends StatelessWidget {
  final String text;
  const _BenefitRow({required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(
          color: AppColors.primary, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(text,
          style: TextStyle(color: context.cl.textS, fontSize: 13.5, height: 1.3)),
      ),
    ],
  ).animate().fadeIn(duration: 350.ms, delay: 100.ms);
}
