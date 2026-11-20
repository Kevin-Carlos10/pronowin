import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../../data/datasources/apple_auth_service.dart';
import '../providers/apres_connexion.dart';
import '../providers/auth_provider.dart';
import '../widgets/bouton_fournisseur.dart';
import '../../../../shared/utils/retour.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../../../core/config/pages_legales.dart';
import '../../../../core/services/analyse_usage.dart';
import '../../../../shared/utils/messages.dart';
import 'package:pronowin/core/config/sans_pari.dart';

/// Ou revenir quand la page a ete ouverte sans historique —
/// par un lien profond de notification, qui remplace la pile.
const _repli = '/home';

/// Largeur de lecture de l'écran de connexion. Sur iPad — l'appareil des
/// relecteurs d'Apple —, des boutons de toute la largeur de l'écran
/// faisaient une page vide au milieu de laquelle flottaient trois bandes.
const largeurConnexion = 420.0;

/// Une adresse plausible : quelque chose, une arobase, un domaine avec un
/// point. Le serveur reste juge ; ceci évite seulement un aller-retour pour
/// « awa.gmail.com ».
final _adresseEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Écran de connexion — accessible uniquement à la demande (bouton « Se
/// connecter » ou accès à une fonctionnalité réservée). L'application
/// elle-même reste consultable sans compte.
///
/// Refait le 20 novembre 2026, au dessin des Paramètres : l'icône de l'app et
/// le nom sur un halo de la marque, une phrase qui dit à quoi sert le compte,
/// puis les chemins de connexion, tous du même poids. Pas de choix
/// « connexion ou inscription » à faire soi-même : le serveur sait si
/// l'adresse existe déjà.
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

  /// Le fournisseur choisi en dernier, pour la mesure de l'entonnoir (M2).
  String _fournisseur = 'google';

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
    final enCours = authState is AuthLoading;

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is AuthAuthenticated) {
        // Cas manquant jusqu'ici. Le chemin e-mail se termine sur l'écran du
        // code, qui gérait cette étape ; la connexion Google aboutit
        // directement ici, et rien ne l'écoutait. L'utilisateur se retrouvait
        // authentifié devant un écran de connexion qu'il devait refermer
        // lui-même — pendant que ses données restaient celles d'un invité et
        // que son jeton de notification restait orphelin.
        apresConnexionReussie(ref);
        // Seules les connexions Google et Apple aboutissent ici. Elles ne
        // disent pas si le compte vient d'être créé : un compte de moins de
        // cinq minutes l'est.
        AnalyseUsage.connexion(methode: _fournisseur,
          nouveauCompte: DateTime.now().difference(state.user.createdAt) < const Duration(minutes: 5));
        context.go(widget.from ?? '/home');
      } else if (state is EmailOtpSent) {
        context.push('/auth/email/otp', extra: {
          'email':     state.email,
          'isNewUser': state.isNewUser,
          'from':      widget.from,
        });
      } else if (state is AuthError) {
        HapticFeedback.mediumImpact();
        afficherMessage(context, state.message, type: TypeMessage.erreur);
      }
    });

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
                tooltip: tr(context, "Fermer"),
                icon: Icon(Icons.close_rounded, color: context.cl.textS),
                onPressed: () => retourOuAller(context, repli: _repli),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, contraintes) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  // Centré verticalement tant que le contenu tient ; il défile
                  // dès que le clavier ou un texte agrandi le pousse.
                  constraints: BoxConstraints(minHeight: contraintes.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: largeurConnexion),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EnTeteConnexion(),
                          const SizedBox(height: 32),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _saisieEmail
                                ? _EtapeEmail(
                                    key: const ValueKey('etape-email'),
                                    formKey:    _formKey,
                                    controleur: _emailCtrl,
                                    enCours:    enCours,
                                    onValider:  _submit,
                                    onRetour:   _revenirAuChoix,
                                  )
                                : _ChoixFournisseur(
                                    key: const ValueKey('etape-choix'),
                                    enCours: enCours,
                                    onGoogle: () {
                                      _fournisseur = 'google';
                                      ref.read(authProvider.notifier).loginWithGoogle();
                                    },
                                    // Sur iPhone seulement (règle 4.8 de l'App Store).
                                    onApple: AppleAuthService.disponible
                                        ? () {
                                            _fournisseur = 'apple';
                                            ref.read(authProvider.notifier).loginWithApple();
                                          }
                                        : null,
                                    onEmail: _ouvrirSaisieEmail,
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
            ),
            // En bas, hors du défilement : le consentement reste visible quel
            // que soit l'état de l'écran.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: largeurConnexion),
                child: _Consentement(
                  cgu: () => PagesLegales.ouvrir(
                    context,
                    PagesLegales.cgu(
                      estStore: ref.read(isStoreBuildProvider),
                      sansPari: ref.read(sansPariProvider)),
                    titre: PagesLegales.titreCgu),
                  confidentialite: () => PagesLegales.ouvrir(
                    context, PagesLegales.confidentialite,
                    titre: PagesLegales.titreConfidentialite),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Un halo de l'orange de la marque derrière l'en-tête : il donne du relief
/// à un écran presque vide, sans rien dire de plus. Partagé avec l'écran du
/// code.
class HaloMarque extends StatelessWidget {
  const HaloMarque({super.key});

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    // Le rayon tient dans la boîte (0,48 × 460 < 230, la moitié de sa
    // hauteur) : le halo s'éteint avant ses bords, sans arête visible.
    return Positioned(
      top: -170, left: -80, right: -80,
      child: IgnorePointer(
        child: Container(
          height: 460,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.48,
              colors: [
                AppColors.primary.withValues(alpha: sombre ? 0.22 : 0.12),
                AppColors.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// L'icône de l'app, le nom, et à quoi sert le compte.
///
/// Les trois bénéfices d'autrefois avaient été retirés : l'utilisateur arrive
/// souvent de `GuestLockedView`, qui vient de les lui dire. Il en reste une
/// phrase — on arrive aussi ici depuis les Paramètres, sans rien savoir.
class EnTeteConnexion extends StatelessWidget {
  const EnTeteConnexion({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 76, height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset('assets/images/app_icon.png',
          width: 76, height: 76, semanticLabel: 'PronoWin'),
      ),
    ).animate()
     .fadeIn(duration: 400.ms)
     .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
         duration: 400.ms, curve: Curves.easeOutBack),
    const SizedBox(height: 18),
    const ExcludeSemantics(child: LogotypePronoWin(taille: 30)),
    const SizedBox(height: 10),
    Text(
      tr(context, "Connecte-toi pour retrouver tes suivis, tes alertes et ton Premium sur tous tes appareils."),
      textAlign: TextAlign.center,
      style: TextStyle(color: context.cl.textS, fontSize: 14, height: 1.45),
    ).animate().fadeIn(duration: 400.ms, delay: 80.ms),
  ]);
}

// ─── CHOIX DU CHEMIN ──────────────────────────────────────────────────────────
/// Les fournisseurs, tous du même poids visuel.
///
/// L'ordre n'est pas arbitraire : Google d'abord, parce que c'est le compte
/// que possède la quasi-totalité des utilisateurs Android — le marché visé —
/// et le seul chemin qui ne coûte ni SMS ni e-mail. L'adresse e-mail en
/// dernier, après « ou » : elle reste le repli, plus le chemin principal.
///
/// « Continuer avec Apple » s'insère entre les deux sur iPhone : la règle 4.8
/// de l'App Store l'exige de toute app proposant une connexion tierce comme
/// Google, avec le même poids visuel.
class _ChoixFournisseur extends StatelessWidget {
  final bool enCours;
  final VoidCallback onGoogle;
  /// Absent hors iPhone : le bouton n'est pas affiché.
  final VoidCallback? onApple;
  final VoidCallback onEmail;

  const _ChoixFournisseur({
    super.key,
    required this.enCours,
    required this.onGoogle,
    required this.onEmail,
    this.onApple,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    BoutonFournisseur(
      libelle: tr(context, "Continuer avec Google"),
      logo: const LogoGoogle(),
      desactive: enCours,
      onPressed: onGoogle,
    ).animate().fadeIn(duration: 400.ms, delay: 140.ms)
     .slideY(begin: 0.06, end: 0, duration: 400.ms),

    if (onApple != null) ...[
      const SizedBox(height: 10),
      BoutonFournisseur(
        libelle: tr(context, "Continuer avec Apple"),
        logo: const LogoApple(),
        desactive: enCours,
        onPressed: onApple!,
      ).animate().fadeIn(duration: 400.ms, delay: 165.ms)
       .slideY(begin: 0.06, end: 0, duration: 400.ms),
    ],

    const _SeparateurOu(),

    BoutonFournisseur(
      libelle: tr(context, "Continuer avec un e-mail"),
      logo: const LogoEmail(),
      desactive: enCours,
      onPressed: onEmail,
    ).animate().fadeIn(duration: 400.ms, delay: 190.ms)
     .slideY(begin: 0.06, end: 0, duration: 400.ms),

    const SizedBox(height: 18),

    // Ce qui arrête le plus souvent à l'inscription : un mot de passe de
    // plus à inventer. Il n'y en a pas.
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.lock_outline_rounded, size: 15, color: context.cl.textS),
      const SizedBox(width: 6),
      Flexible(child: Text(tr(context, "Sans mot de passe, en quelques secondes"),
        style: TextStyle(color: context.cl.textS, fontSize: 13))),
    ]).animate().fadeIn(duration: 400.ms, delay: 230.ms),
  ]);
}

/// « ou » entre les comptes (Google, Apple) et l'adresse e-mail.
class _SeparateurOu extends StatelessWidget {
  const _SeparateurOu();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [
      Expanded(child: Divider(color: context.cl.border, height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(tr(context, "ou"),
          style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Divider(color: context.cl.border, height: 1)),
    ]),
  );
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
    super.key,
    required this.formKey,
    required this.controleur,
    required this.enCours,
    required this.onValider,
    required this.onRetour,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Form(
        key: formKey,
        child: TextFormField(
          key: const Key('connexion-email'),
          controller: controleur,
          // L'utilisateur vient de demander explicitement ce chemin : lui faire
          // toucher le champ une seconde fois serait un appui de trop.
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          // Laisse le gestionnaire de mots de passe et la saisie automatique
          // proposer l'adresse.
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          onFieldSubmitted: (_) => onValider(),
          style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: tr(context, "Adresse email"),
            hintText: tr(context, "nom@exemple.com"),
            prefixIcon: Icon(Icons.mail_outline_rounded, color: context.cl.textS),
          ),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return tr(context, "Email requis");
            if (!_adresseEmail.hasMatch(s)) return tr(context, "Email invalide");
            return null;
          },
        ),
      ),

      const SizedBox(height: 10),
      Text(tr(context, "Tu recevras un code à 6 chiffres. Aucun mot de passe à créer."),
        style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4)),

      const SizedBox(height: 18),

      PwButton(
        label: tr(context, "Recevoir mon code"),
        isLoading: enCours,
        onPressed: onValider,
      ),

      const SizedBox(height: 6),

      // Sortie de secours : sans elle, choisir l'e-mail par erreur enfermerait
      // l'utilisateur dans une étape qu'il n'a plus moyen de quitter autrement
      // que par la croix, qui referme tout l'écran.
      Center(
        child: TextButton.icon(
          onPressed: enCours ? null : onRetour,
          icon: Icon(Icons.arrow_back_rounded, size: 16, color: context.cl.textS),
          label: Text(tr(context, "Autres options de connexion"),
            style: TextStyle(color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    ],
  ).animate().fadeIn(duration: 300.ms);
}

/// Seul recueil de consentement depuis la suppression de l'écran de CGU :
/// cette mention doit être lisible, pas décorative — `textS` (~6:1), pas
/// `textM` (2,5:1). `Text.rich` plutôt que `RichText` : il suit la taille de
/// texte choisie dans le téléphone.
class _Consentement extends StatefulWidget {
  final VoidCallback cgu, confidentialite;
  const _Consentement({required this.cgu, required this.confidentialite});

  @override
  State<_Consentement> createState() => _ConsentementState();
}

class _ConsentementState extends State<_Consentement> {
  late final _toucheCgu = TapGestureRecognizer()..onTap = widget.cgu;
  late final _toucheConfidentialite = TapGestureRecognizer()..onTap = widget.confidentialite;

  @override
  void dispose() {
    _toucheCgu.dispose();
    _toucheConfidentialite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lien = TextStyle(
      color: context.cl.accent, decoration: TextDecoration.underline, fontWeight: FontWeight.w600);
    return Text.rich(
      key: const Key('connexion-consentement'),
      textAlign: TextAlign.center,
      TextSpan(
        style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.45),
        children: [
          TextSpan(text: tr(context, "En continuant, tu acceptes nos ")),
          TextSpan(text: tr(context, "conditions d'utilisation"), style: lien, recognizer: _toucheCgu),
          TextSpan(text: tr(context, " et notre ")),
          TextSpan(text: tr(context, "politique de confidentialité"), style: lien,
            recognizer: _toucheConfidentialite),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
