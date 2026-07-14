import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class TermsPage extends ConsumerStatefulWidget {
  const TermsPage({super.key});

  @override
  ConsumerState<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends ConsumerState<TermsPage> {
  bool _accepted   = false;
  bool _scrolledEnd = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (!_scrolledEnd &&
          _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 60) {
        setState(() => _scrolledEnd = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_accepted) return;
    await ref.read(authProvider.notifier).acceptTerms();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state is TermsAccepted) context.go('/home');
      if (state is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating));
      }
    });

    final isLoading = authState is AuthLoading;

    return Scaffold(
      backgroundColor: context.cl.bg,
      body: SafeArea(
        child: Column(children: [

          // ── Header ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Conditions d\'utilisation', style: TextStyle(
                    color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Lisez et acceptez avant de continuer', style: TextStyle(
                    color: context.cl.textS, fontSize: 12)),
                ])),
              ]).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0),

              const SizedBox(height: 12),

              // Barre de progression lecture
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: context.cl.border,
                  borderRadius: BorderRadius.circular(2)),
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 300),
                  widthFactor: _scrolledEnd ? 1.0 : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(2))))),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Corps CGU ─────────────────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cl.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.cl.border, width: 0.5)),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: const CguContent()),
            ),
          ),

          // ── Zone acceptation ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(children: [
              if (!_scrolledEnd)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.keyboard_arrow_down_rounded,
                      color: context.cl.textM, size: 16),
                    const SizedBox(width: 4),
                    Text('Faites défiler jusqu\'en bas pour continuer',
                      style: TextStyle(color: context.cl.textM, fontSize: 11)),
                  ]),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 600.ms),

              // Checkbox
              GestureDetector(
                onTap: _scrolledEnd ? () => setState(() => _accepted = !_accepted) : null,
                child: AnimatedOpacity(
                  opacity: _scrolledEnd ? 1.0 : 0.35,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _accepted
                        ? AppColors.success.withValues(alpha: 0.08)
                        : context.cl.surfaceDeep,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _accepted ? AppColors.success : context.cl.border,
                        width: _accepted ? 1.5 : 0.5)),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: _accepted ? AppColors.success : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _accepted ? AppColors.success : context.cl.textM,
                            width: 1.5)),
                        child: _accepted
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                          : null),
                      const SizedBox(width: 12),
                      Expanded(child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.4),
                          children: [
                            const TextSpan(text: "J'ai lu et j'accepte les "),
                            TextSpan(
                              text: 'conditions d\'utilisation',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _scrollCtrl.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOut)),
                            const TextSpan(text: ' et la '),
                            TextSpan(
                              text: 'politique de confidentialité',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {}),
                            const TextSpan(text: ' de PronoWin.'),
                          ],
                        ),
                      )),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Bouton
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: (_accepted && !isLoading) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: context.cl.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
                  child: isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Accepter et continuer',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── CONTENU CGU (public — réutilisé dans LegalPage) ─────────────────────────
class CguContent extends StatelessWidget {
  const CguContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Section('1. Présentation de PronoWin',
        'PronoWin est une application mobile proposant des analyses et pronostics sportifs à titre informatif. PronoWin n\'est pas un opérateur de jeux d\'argent. Aucune mise réelle n\'est effectuée via l\'application.'),
      _Section('2. Conditions d\'accès',
        'L\'utilisation de PronoWin est réservée aux personnes majeures (18 ans ou plus). En créant un compte, vous certifiez avoir l\'âge légal requis dans votre pays de résidence pour accéder à des contenus liés aux paris sportifs.'),
      _Section('3. Pronostics — caractère informatif',
        'Les analyses publiées sur PronoWin sont fournies à titre indicatif uniquement. Elles ne constituent en aucun cas des garanties de résultats. Tout pari effectué reste sous votre entière responsabilité.'),
      _Section('4. Abonnement Premium',
        'L\'accès Premium débloque les pronostics VIP et les analyses IA. L\'abonnement est mensuel et non remboursable une fois activé. PronoWin se réserve le droit de modifier les tarifs avec un préavis de 30 jours.'),
      _Section('5. Code 1xBet',
        'L\'activation via code 1xBet est gratuite. Elle est soumise à vérification par notre équipe sous 24h ouvrées. Tout abus (faux comptes, captures falsifiées) entraînera la suspension définitive du compte.'),
      _Section('6. Données personnelles',
        'PronoWin collecte votre numéro de téléphone et vos données d\'utilisation dans le respect du RGPD et des lois locales applicables. Vos données ne sont jamais revendues à des tiers. Vous pouvez demander la suppression de votre compte à tout moment depuis les paramètres.'),
      _Section('7. Jeu responsable',
        'PronoWin encourage le jeu responsable. Ne misez jamais plus que ce que vous pouvez vous permettre de perdre. Si vous pensez souffrir d\'une dépendance aux jeux d\'argent, contactez une ligne d\'aide spécialisée dans votre pays.'),
      _Section('8. Propriété intellectuelle',
        'L\'ensemble du contenu de PronoWin (analyses, design, algorithmes IA, logo) est la propriété exclusive de PronoWin. Toute reproduction ou diffusion sans autorisation est interdite.'),
      _Section('9. Limitation de responsabilité',
        'PronoWin ne peut être tenu responsable des pertes financières résultant de l\'utilisation de ses pronostics. L\'application est fournie "telle quelle" sans garantie de disponibilité permanente.'),
      _Section('10. Modification des CGU',
        'Ces conditions peuvent être mises à jour. En cas de modification substantielle, vous serez invité à les relire et les accepter à nouveau lors de votre prochaine connexion.'),
      _Section('11. Contact',
        'Pour toute question ou réclamation : support@pronowin.app'),
      const SizedBox(height: 8),
      Text('Dernière mise à jour : Juin 2026',
        style: TextStyle(color: context.cl.textM, fontSize: 11,
          fontStyle: FontStyle.italic)),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section(this.title, this.body);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(
        color: context.cl.textP, fontSize: 13,
        fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(body, style: TextStyle(
        color: context.cl.textS, fontSize: 12.5, height: 1.6)),
    ]),
  );
}
