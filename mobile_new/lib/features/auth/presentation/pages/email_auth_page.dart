import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
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

/// Écran de connexion — accessible uniquement à la demande (bouton « Se
/// connecter » ou accès à une fonctionnalité réservée). L'application
/// elle-même reste consultable sans compte.
///
/// Refait le 24 novembre 2026 d'après l'écran « Connexion ou inscription »
/// montré par l'utilisateur : une feuille claire aux coins arrondis posée sur
/// le bleu nuit, deux boutons ronds (retour, fermer) autour du titre, une
/// carte de ce qu'apporte un compte — trois avantages réels, rien d'inventé —,
/// puis les chemins de connexion en rectangles de même taille, et le
/// consentement juste dessous. Pas de choix « connexion ou inscription » à
/// faire soi-même : le serveur sait si l'adresse existe déjà.
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

  void _fermer() => retourOuAller(context, repli: _repli);

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

    // Derrière la feuille : le bleu nuit de la marque, noir en thème sombre
    // pour que la feuille s'en détache encore.
    final fond = context.isDark ? Colors.black : const Color(0xFF0D1530);
    final feuille = _couleurFeuille(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Icônes de la barre d'état en blanc, sur le fond nuit.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: fond,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              key: const Key('connexion-feuille'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: feuille,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                _EnTete(
                  // Le retour ramène au choix depuis la saisie de l'adresse ;
                  // ailleurs, il referme l'écran, comme la croix.
                  onRetour: _saisieEmail && !enCours ? _revenirAuChoix : _fermer,
                  onFermer: _fermer,
                ),
                Expanded(
                  child: LayoutBuilder(builder: (context, contraintes) => SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: contraintes.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: largeurConnexion),
                              child: Column(children: [
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
                                const SizedBox(height: 16),
                                // Le consentement, sous les chemins, quel que
                                // soit l'état de l'écran.
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
                          const Spacer(),
                          SafeArea(
                            top: false,
                            minimum: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextButton(
                                key: const Key('connexion-aide'),
                                // Un objet déjà rempli : la demande se traite
                                // sans échange préalable.
                                onPressed: () => ContactSupport.ouvrirEmail(
                                  sujet: tr(context, "Problème de connexion")),
                                style: TextButton.styleFrom(foregroundColor: context.cl.textS),
                                child: Text(tr(context, "Besoin d'aide ?"),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  )),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// La feuille : blanche en thème clair, comme le modèle ; le fond de page en
/// thème sombre, qui se détache du noir qui l'entoure.
Color _couleurFeuille(BuildContext context) =>
    context.isDark ? context.cl.bg : context.cl.surface;

/// Le haut de la feuille : retour et fermeture en boutons ronds, le titre
/// entre les deux.
class _EnTete extends StatelessWidget {
  final VoidCallback onRetour;
  final VoidCallback onFermer;
  const _EnTete({required this.onRetour, required this.onFermer});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
    child: Row(children: [
      _BoutonRond(icone: Icons.chevron_left_rounded, infobulle: tr(context, "Retour"), onTap: onRetour),
      const SizedBox(width: 8),
      Expanded(
        child: Semantics(
          header: true,
          child: Text(tr(context, "Connexion ou inscription"),
            key: const Key('connexion-titre'),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: context.cl.textP, fontSize: 20,
              fontWeight: FontWeight.w700, height: 1.2)),
        ),
      ),
      const SizedBox(width: 8),
      _BoutonRond(icone: Icons.close_rounded, infobulle: tr(context, "Fermer"), onTap: onFermer),
    ]),
  );
}

class _BoutonRond extends StatelessWidget {
  final IconData icone;
  final String infobulle;
  final VoidCallback onTap;
  const _BoutonRond({required this.icone, required this.infobulle, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: infobulle,
    child: Material(
      color: _couleurFeuille(context),
      shape: CircleBorder(side: BorderSide(color: context.cl.border, width: 1)),
      elevation: context.isDark ? 0 : 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46, height: 46,
          child: Icon(icone, size: 26, color: context.cl.textP),
        ),
      ),
    ),
  );
}

/// Ce qu'apporte un compte, en trois avantages qui existent vraiment :
/// suivre ses équipes, recevoir les alertes de ses matchs suivis, retrouver
/// ses favoris sur un autre téléphone (ils sont gardés sur le serveur, liés
/// au compte).
class _Avantages extends StatelessWidget {
  const _Avantages();

  @override
  Widget build(BuildContext context) {
    final avantages = [
      (Icons.star_border_rounded, tr(context, "Suis tes équipes favorites")),
      (Icons.notifications_none_rounded, tr(context, "Alertes de tes matchs suivis")),
      (Icons.devices_outlined, tr(context, "Tes favoris sur tous tes appareils")),
    ];
    return Container(
      key: const Key('connexion-avantages'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
      decoration: BoxDecoration(
        color: context.isDark
            ? context.cl.surface
            : context.cl.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Text(tr(context, "Profite pleinement de PronoWin"),
          key: const Key('connexion-accroche'),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textP, fontSize: 21,
            fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.2)),
        const SizedBox(height: 8),
        Text(tr(context, "Gratuit et sans mot de passe. Inscris-toi en quelques secondes !"),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.cl.textS, fontSize: 15, height: 1.4)),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (icone, texte) in avantages)
            Expanded(child: Column(children: [
              Icon(icone, size: 32, color: context.cl.textP),
              const SizedBox(height: 8),
              Text(texte,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textP, fontSize: 14, height: 1.3)),
            ])),
        ]),
      ]),
    ).animate().fadeIn(duration: 350.ms);
  }
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
/// Les avantages d'un compte, puis les fournisseurs, tous de la même forme.
///
/// L'ordre n'est pas arbitraire : Google d'abord, parce que c'est le compte
/// que possède la quasi-totalité des utilisateurs Android — le marché visé —
/// et le seul chemin qui ne coûte ni SMS ni e-mail. L'adresse e-mail en
/// dernier : elle reste le repli, plus le chemin principal.
///
/// « Continuer avec Apple » s'insère entre les deux sur iPhone : la règle 4.8
/// de l'App Store l'exige de toute app proposant une connexion tierce comme
/// Google. Il est plein, noir (blanc en thème sombre), comme le veulent les
/// règles de présentation d'Apple.
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
    const _Avantages(),
    const SizedBox(height: 28),

    BoutonFournisseur(
      libelle: tr(context, "Continuer avec Google"),
      logo: const LogoGoogle(),
      desactive: enCours,
      onPressed: onGoogle,
    ).animate().fadeIn(duration: 400.ms, delay: 120.ms)
     .slideY(begin: 0.06, end: 0, duration: 400.ms),

    if (onApple != null) ...[
      const SizedBox(height: 14),
      BoutonFournisseur(
        libelle: tr(context, "Continuer avec Apple"),
        logo: const LogoApple(),
        plein: true,
        desactive: enCours,
        onPressed: onApple!,
      ).animate().fadeIn(duration: 400.ms, delay: 145.ms)
       .slideY(begin: 0.06, end: 0, duration: 400.ms),
    ],

    const SizedBox(height: 14),

    BoutonFournisseur(
      libelle: tr(context, "Continuer avec un e-mail"),
      logo: const LogoEmail(),
      desactive: enCours,
      onPressed: onEmail,
    ).animate().fadeIn(duration: 400.ms, delay: 170.ms)
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
      color: context.cl.textS, decoration: TextDecoration.underline, fontWeight: FontWeight.w600);
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
