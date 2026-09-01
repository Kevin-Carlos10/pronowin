import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../providers/apres_connexion.dart';
import '../providers/auth_provider.dart';
import '../widgets/bouton_fournisseur.dart';

/// Écran de connexion — accessible uniquement à la demande (bouton « Se
/// connecter » ou accès à une fonctionnalité réservée). L'application
/// elle-même reste consultable sans compte.
///
/// Réduit à sa plus simple expression : le nom, puis les chemins de connexion,
/// tous du même poids. Pas d'argumentaire — celui-ci est déjà tenu par l'écran
/// d'où l'on vient — et pas de choix « connexion ou inscription » à faire
/// soi-même : le serveur sait si l'adresse existe déjà.
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

  /// L'écran a deux états : le choix du chemin, puis la saisie de l'adresse.
  ///
  /// Le champ était visible d'emblée, surmonté du seul bouton plein de la page
  /// — l'e-mail devenait de fait le chemin par défaut, alors qu'il est le plus
  /// lent pour l'utilisateur et le seul à coûter un envoi. Il reste offert,
  /// mais à égalité, et sa saisie n'occupe l'écran que si on la demande.
  bool _saisieEmail = false;

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

  void _ouvrirSaisieEmail() {
    HapticFeedback.selectionClick();
    setState(() => _saisieEmail = true);
  }

  void _revenirAuChoix() {
    FocusScope.of(context).unfocus();
    setState(() => _saisieEmail = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        // Cas manquant jusqu'ici. Le chemin e-mail se termine sur l'écran du
        // code, qui gérait cette étape ; la connexion Google aboutit
        // directement ici, et rien ne l'écoutait. L'utilisateur se retrouvait
        // authentifié devant un écran de connexion qu'il devait refermer
        // lui-même — pendant que ses données restaient celles d'un invité et
        // que son jeton de notification restait orphelin.
        apresConnexionReussie(ref);
        context.go(widget.from ?? '/home');
      } else if (state is EmailOtpSent) {
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
                      // Le nom seul, sans tuile ni argumentaire.
                      //
                      // Les trois bénéfices ont été retirés parce que
                      // l'utilisateur arrive de `GuestLockedView`, qui vient
                      // justement de lui dire ce qu'il gagne à créer un compte :
                      // les répéter retardait l'action au lieu de la motiver.
                      //
                      // La tuile au trophée l'a suivi : elle redisait en icône
                      // ce que le mot énonce, à l'écran même où l'utilisateur
                      // vient de toucher cette icône dans le lanceur. Le
                      // logotype porte seul la marque, et il grandit d'autant.
                      const LogotypePronoWin(taille: 34)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
                            duration: 400.ms, curve: Curves.easeOutBack),

                      const SizedBox(height: 44),

                      if (_saisieEmail)
                        _EtapeEmail(
                          formKey:   _formKey,
                          controleur: _emailCtrl,
                          enCours:   authState is AuthLoading,
                          onValider: _submit,
                          onRetour:  _revenirAuChoix,
                        )
                      else
                        _ChoixFournisseur(
                          enCours: authState is AuthLoading,
                          onGoogle: () => ref
                              .read(authProvider.notifier)
                              .loginWithGoogle(),
                          onEmail: _ouvrirSaisieEmail,
                        ),

                      const SizedBox(height: 20),

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

// ─── CHOIX DU CHEMIN ──────────────────────────────────────────────────────────
/// Les fournisseurs, tous du même poids visuel.
///
/// L'ordre n'est pas arbitraire : Google d'abord, parce que c'est le compte
/// que possède la quasi-totalité des utilisateurs Android — le marché visé —
/// et le seul chemin qui ne coûte ni SMS ni e-mail. L'adresse e-mail en
/// dernier : elle reste le repli, plus le chemin principal.
///
/// « Continuer avec Apple » viendra s'insérer entre les deux dès la sortie
/// iOS : la règle 4.8 de l'App Store l'exige de toute app proposant une
/// connexion tierce comme Google. La pile est faite pour l'accueillir sans
/// retoucher l'écran.
class _ChoixFournisseur extends StatelessWidget {
  final bool enCours;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;

  const _ChoixFournisseur({
    required this.enCours,
    required this.onGoogle,
    required this.onEmail,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    BoutonFournisseur(
      libelle: 'Continuer avec Google',
      logo: const LogoGoogle(),
      desactive: enCours,
      onPressed: onGoogle,
    ).animate().fadeIn(duration: 400.ms, delay: 140.ms)
     .slideY(begin: 0.06, end: 0, duration: 400.ms),

    const SizedBox(height: 11),

    BoutonFournisseur(
      libelle: 'Continuer avec un e-mail',
      logo: const LogoEmail(),
      desactive: enCours,
      onPressed: onEmail,
    ).animate().fadeIn(duration: 400.ms, delay: 190.ms)
     .slideY(begin: 0.06, end: 0, duration: 400.ms),
  ]);
}

// ─── SAISIE DE L'ADRESSE ──────────────────────────────────────────────────────
/// Seconde étape du chemin par e-mail.
class _EtapeEmail extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controleur;
  final bool enCours;
  final VoidCallback onValider;
  final VoidCallback onRetour;

  const _EtapeEmail({
    required this.formKey,
    required this.controleur,
    required this.enCours,
    required this.onValider,
    required this.onRetour,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    Form(
      key: formKey,
      child: TextFormField(
        controller: controleur,
        // L'utilisateur vient de demander explicitement ce chemin : lui faire
        // toucher le champ une seconde fois serait un appui de trop.
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        // Laisse le gestionnaire de mots de passe et la saisie automatique
        // proposer l'adresse.
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        enableSuggestions: false,
        onFieldSubmitted: (_) => onValider(),
        style: TextStyle(
          color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(hintText: 'Adresse email'),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Email requis';
          if (!v.contains('@')) return 'Email invalide';
          return null;
        },
      ),
    ),

    const SizedBox(height: 16),

    SizedBox(
      width: double.infinity,
      child: PwButton(
        label: 'Recevoir mon code',
        isLoading: enCours,
        onPressed: onValider,
      ),
    ),

    const SizedBox(height: 6),

    // Sortie de secours : sans elle, choisir l'e-mail par erreur enfermerait
    // l'utilisateur dans une étape qu'il n'a plus moyen de quitter autrement
    // que par la croix, qui referme tout l'écran.
    TextButton(
      onPressed: enCours ? null : onRetour,
      child: Text('Autres options de connexion',
        style: TextStyle(
          color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
    ),
  ]).animate().fadeIn(duration: 300.ms);
}

