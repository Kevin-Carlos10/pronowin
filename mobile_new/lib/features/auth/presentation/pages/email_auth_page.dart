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
import '../../../../core/config/contact_support.dart';
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

/// Le bandeau de la marque, plus sombre que l'orange des boutons : le texte
/// blanc y tient 4,5:1 (#D2470E), et davantage vers le bas (#A8330A).
const _bandeau = [Color(0xFFD2470E), Color(0xFFA8330A)];

/// Écran de connexion — accessible uniquement à la demande (bouton « Se
/// connecter » ou accès à une fonctionnalité réservée). L'application
/// elle-même reste consultable sans compte.
///
/// Refait le 20 novembre 2026 d'après l'écran de connexion d'Alibaba, montré
/// par l'utilisateur : un grand bandeau de la marque en haut (le nom, une
/// accroche, une petite scène), une colline du fond de page qui le borde, puis
/// les chemins de connexion en pilules, tous du même poids, et « Besoin
/// d'aide ? ». Pas de choix « connexion ou inscription » à faire soi-même : le
/// serveur sait si l'adresse existe déjà.
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

    final media = MediaQuery.of(context);
    // Clavier ouvert (saisie de l'adresse) : le bandeau se replie pour
    // laisser le champ et son bouton à l'écran.
    final clavier = media.viewInsets.bottom > 0;
    final hauteurBandeau = clavier
        ? (media.padding.top + 150)
        : (media.size.height * 0.46).clamp(330.0, 460.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Icônes de la barre d'état en blanc, sur le bandeau.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: context.cl.bg,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(builder: (context, contraintes) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: contraintes.maxHeight),
            child: IntrinsicHeight(
              child: Column(children: [
                _Bandeau(
                  hauteur: hauteurBandeau.toDouble(),
                  compact: clavier,
                  onFermer: () => retourOuAller(context, repli: _repli),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: largeurConnexion),
                    child: AnimatedSwitcher(
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
                  ),
                ),
                const Spacer(),
                // En bas : de l'aide, et le consentement, visible quel que
                // soit l'état de l'écran.
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: largeurConnexion),
                      child: Column(children: [
                        TextButton(
                          key: const Key('connexion-aide'),
                          // Un objet déjà rempli : la demande se traite sans
                          // échange préalable.
                          onPressed: () => ContactSupport.ouvrirEmail(
                            sujet: tr(context, "Problème de connexion")),
                          style: TextButton.styleFrom(foregroundColor: context.cl.textS),
                          child: Text(tr(context, "Besoin d'aide ?"),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 4),
                        _Consentement(
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
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        )),
      ),
    );
  }
}

/// Le bandeau de la marque : le nom, la fermeture, une accroche et une petite
/// scène. Le fond de page le borde d'une colline, sur laquelle la scène pose.
class _Bandeau extends StatelessWidget {
  final double hauteur;
  /// Clavier ouvert : le nom et la croix seulement.
  final bool compact;
  final VoidCallback onFermer;
  const _Bandeau({required this.hauteur, required this.compact, required this.onFermer});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    // Toute la largeur : sans elle, le bandeau replié (clavier ouvert) se
    // réduisait à la largeur du nom.
    width: double.infinity,
    height: hauteur,
    child: Stack(children: [
      Positioned.fill(
        child: ClipPath(
          clipper: const _Colline(),
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              colors: _bandeau, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          ),
        ),
      ),
      SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 52,
            width: double.infinity,
            child: Stack(alignment: Alignment.center, children: [
              const ExcludeSemantics(child: LogotypePronoWin(taille: 26, toutBlanc: true)),
              Positioned(
                right: 4,
                child: IconButton(
                  tooltip: tr(context, "Fermer"),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: onFermer,
                ),
              ),
            ]),
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(children: [
                Text(tr(context, "Le foot au quotidien, avec"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(tr(context, "pronostics, scores en direct & alertes"),
                  key: const Key('connexion-accroche'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.4)),
              ]),
            ).animate().fadeIn(duration: 400.ms),
            const Expanded(child: _Scene()),
          ],
        ]),
      ),
    ]),
  );
}

/// Le bas du bandeau : le fond de page monte en colline au milieu.
class _Colline extends CustomClipper<Path> {
  const _Colline();

  @override
  Path getClip(Size s) {
    final bosse = (s.height * 0.16).clamp(28.0, 64.0);
    return Path()
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..quadraticBezierTo(s.width / 2, s.height - 2 * bosse, 0, s.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _Colline oldClipper) => false;
}

/// La petite scène du bandeau : l'icône de l'app, et autour ce que l'app
/// fait — un score, le direct, une alerte, un classement. Composée de
/// widgets, sans image : elle suit le thème et ne pèse rien. Rien n'y bouge
/// après l'entrée.
class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: SizedBox(
        width: 300, height: 150,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          // L'icône, au centre, cerclée de blanc pour se détacher de l'orange.
          Container(
            width: 96, height: 96,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22, offset: const Offset(0, 10))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 80.ms)
           .scale(begin: const Offset(0.85, 0.85), duration: 450.ms, curve: Curves.easeOutBack),

          // En direct, en haut à gauche.
          Positioned(left: 14, top: 8, child: _Pastille(
            couleur: Colors.black.withValues(alpha: 0.28),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7,
                decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(tr(context, "EN DIRECT"),
                style: const TextStyle(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ]),
          )).animate().fadeIn(duration: 350.ms, delay: 200.ms).moveY(begin: 8, end: 0),

          // Un score, en bas à gauche.
          Positioned(left: 0, bottom: 14, child: _Pastille(
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.sports_soccer_rounded, size: 16, color: Color(0xFF1F2430)),
              SizedBox(width: 6),
              Text('2 - 1', style: TextStyle(color: Color(0xFF1F2430), fontSize: 14,
                fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          )).animate().fadeIn(duration: 350.ms, delay: 260.ms).moveY(begin: 8, end: 0),

          // Une alerte, en haut à droite.
          Positioned(right: 18, top: 4, child: _Bulle(
            icone: Icons.notifications_active_rounded, pastille: true,
          )).animate().fadeIn(duration: 350.ms, delay: 320.ms).moveY(begin: 8, end: 0),

          // Le classement, en bas à droite.
          Positioned(right: 2, bottom: 18, child: _Bulle(
            icone: Icons.leaderboard_rounded,
          )).animate().fadeIn(duration: 350.ms, delay: 380.ms).moveY(begin: 8, end: 0),
        ]),
      ),
    ),
  );
}

/// Une pastille arrondie de la scène : blanche par défaut.
class _Pastille extends StatelessWidget {
  final Widget child;
  final Color couleur;
  const _Pastille({required this.child, this.couleur = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: couleur,
      borderRadius: BorderRadius.circular(20),
      boxShadow: couleur == Colors.white
          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))]
          : null,
    ),
    child: child,
  );
}

/// Une bulle ronde blanche et son icône orange, avec au besoin le point rouge
/// d'une notification.
class _Bulle extends StatelessWidget {
  final IconData icone;
  final bool pastille;
  const _Bulle({required this.icone, this.pastille = false});

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
    Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: Colors.white, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Icon(icone, size: 22, color: const Color(0xFFD2470E)),
    ),
    if (pastille) Positioned(right: 2, top: 2, child: Container(
      width: 11, height: 11,
      decoration: BoxDecoration(color: const Color(0xFFFF3B30), shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2)),
    )),
  ]);
}

/// Un halo de l'orange de la marque derrière l'en-tête de l'écran du code :
/// il donne du relief à un écran presque vide, sans rien dire de plus.
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
      const SizedBox(height: 14),
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

    const SizedBox(height: 16),

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
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [
      Expanded(child: Divider(color: context.cl.border, height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(tr(context, "ou"),
          style: TextStyle(color: context.cl.textS, fontSize: 14, fontWeight: FontWeight.w500)),
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
      const SizedBox(height: 8),
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
