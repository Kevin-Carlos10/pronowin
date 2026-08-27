import 'package:country_picker/country_picker.dart'
    show CountryService, CountryLocalizations;
import 'package:flutter/material.dart';
import '../../../../core/widgets/image_distante.dart';
import '../../../../core/utils/motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/utils/premium_nav.dart';
import '../../../../features/abonnement/presentation/providers/subscription_provider.dart';
import '../../../../features/parrainage/presentation/providers/referral_provider.dart';
import '../providers/compte_provider.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/montant.dart';
import '../../../bankroll/presentation/providers/bankroll_provider.dart';
import '../../../abonnement/presentation/providers/iap_provider.dart';
import '../../../../shared/utils/bilan_paris.dart';
import '../../../../shared/widgets/bottom_nav_metrics.dart';

class ComptePage extends ConsumerStatefulWidget {
  const ComptePage({super.key});
  @override
  ConsumerState<ComptePage> createState() => _ComptePageState();
}

class _ComptePageState extends ConsumerState<ComptePage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final subAsync     = ref.watch(currentSubscriptionProvider);
    ref.watch(referralStatsProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (_, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 80, height: 80,
                decoration: BoxDecoration(
                  color: context.cl.surface, shape: BoxShape.circle,
                  border: Border.all(color: context.cl.border, width: 0.5)),
                child: Icon(Icons.wifi_off_rounded,
                  color: context.cl.textM, size: 38)),
              const SizedBox(height: 20),
              Text('Connexion impossible',
                style: TextStyle(color: context.cl.textP,
                  fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Impossible de charger ton profil.\nVérifie ta connexion.',
                style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => ref.invalidate(profileProvider),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Réessayer', style: TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
        )),
      data: (profile) {
        final pseudo      = profile['pseudo']           as String? ?? 'Parieur';
        final phone       = profile['phone_number']     as String? ?? '';
        final email       = profile['email']            as String? ?? '';
        final country     = profile['country_code']     as String? ?? '';
        final firstName   = profile['first_name']       as String? ?? '';
        final lastName    = profile['last_name']        as String? ?? '';
        final birthDate   = profile['birth_date']       as String?;
        final fullName    = firstName.isNotEmpty && lastName.isNotEmpty
                              ? '$firstName $lastName' : '';
        final plan        = profile['subscription_plan'] as String? ?? 'free';
        final isPremium   = plan == 'premium';
        final createdAt   = profile['created_at']       as String?;
        final referralCode = profile['referral_code']   as String? ?? '------';
        final earnings    = (profile['referral_earnings'] as num?)?.toInt() ?? 0;
        final avatarUrl   = profile['avatar_url']       as String?;
        final displayName = fullName.isNotEmpty ? fullName : pseudo;
        final initiale    = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P';

        return Scaffold(
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(profileProvider);
              ref.invalidate(currentSubscriptionProvider);
              ref.invalidate(referralStatsProvider);
            },
            child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                // 235 était trop court : le contenu (avatar + nom + pseudo +
                // pastille) débordait sur la TabBar, la pastille « Gratuit »
                // se superposant au libellé « Abonnement ». La zone flexible
                // inclut la TabBar (46px) et la barre d'état.
                expandedHeight: 262,
                pinned: true,
                backgroundColor: context.cl.bg,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: Icon(Icons.settings_rounded, color: context.cl.textS),
                    onPressed: () => context.push('/parametres'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                    onPressed: () => _showLogoutSheet(context, ref),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [context.cl.bg, context.cl.surface],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter)),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            _ProfileAvatar(
                              initiale: initiale,
                              avatarUrl: avatarUrl,
                              isPremium: isPremium,
                              earnings: earnings,
                              onEdit: () => context.push('/compte/edit'),
                            ).animate()
                              .scale(begin: const Offset(0.65, 0.65), end: const Offset(1, 1),
                                duration: 500.ms, curve: Curves.easeOutBack)
                              .fadeIn(duration: 400.ms),
                            const SizedBox(height: 10),
                            Text(displayName, style: TextStyle(
                              color: context.cl.textP,
                              fontSize: 22, fontWeight: FontWeight.w800))
                              .animate(delay: 120.ms)
                              .fadeIn(duration: 300.ms)
                              .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                            // Le pseudo remplace le numéro de téléphone :
                            // afficher son numéro sous son nom l'expose dès
                            // qu'on montre son écran, sans rien apporter. Il
                            // reste consultable dans la fiche d'informations.
                            // Affiché seulement si le nom réel est connu,
                            // sinon le titre EST déjà le pseudo.
                            if (fullName.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text('@$pseudo', style: TextStyle(
                                color: context.cl.textS, fontSize: 13))
                                .animate(delay: 160.ms)
                                .fadeIn(duration: 280.ms),
                            ],
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              _PremiumBadge(isPremium: isPremium),
                              subAsync.when(
                                data: (sub) {
                                  final days = (sub['days_left'] as num?)?.toInt() ?? 0;
                                  return isPremium && days > 0
                                    ? Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _Badge(label: '$days j restants',
                                          color: AppColors.success))
                                    : const SizedBox.shrink();
                                },
                                loading: () => const SizedBox.shrink(),
                                error: (_, _) => const SizedBox.shrink(),
                              ),
                            ]).animate(delay: 200.ms).fadeIn(duration: 300.ms),
                            // Rangée « Plan / Gains / Membre » retirée : le plan
                            // est déjà la pastille juste au-dessus, les gains de
                            // parrainage ont leur onglet dédié (et affichaient
                            // « – »), et l'ancienneté figure dans la fiche
                            // d'informations. L'en-tête garde l'identité seule.
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(46),
                  child: TabBar(
                    controller: _tab,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: context.cl.textS,
                    labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Aperçu'),
                      Tab(text: 'Abonnement'),
                      Tab(text: 'Parrainage'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tab,
              children: [
                _ApercuTab(
                  pseudo: pseudo, phone: phone, email: email,
                  country: country, createdAt: createdAt,
                  firstName: firstName, lastName: lastName,
                  fullName: fullName, birthDate: birthDate,
                  onAbonnementTap: () => _tab.animateTo(1)),
                _AbonnementTab(isPremium: isPremium),
                _ParrainageTab(refCode: referralCode, earnings: earnings),
              ],
            ),
          ),        // NestedScrollView
          ),        // RefreshIndicator
        );
      },
    );
  }

  void _showLogoutSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.cl.border, width: 0.5)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle),
            child: const Icon(Icons.logout_rounded,
              color: AppColors.error, size: 26)),
          const SizedBox(height: 14),
          Text('Déconnexion ?', style: TextStyle(
            color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Vous devrez te reconnecter avec ton adresse email.',
            style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                // Invalider tous les providers mis en cache pour cet utilisateur
                ref.invalidate(isLoggedInProvider);
                ref.invalidate(bankrollProvider);
                ref.invalidate(bankrollStatsProvider);
                ref.invalidate(profileProvider);
                ref.invalidate(userStatsProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  context.go('/home');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
              child: const Text('Me déconnecter',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 46,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler',
                style: TextStyle(color: context.cl.textS, fontSize: 14)))),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// ONGLET APERÇU
// ══════════════════════════════════════════════════════
class _ApercuTab extends ConsumerWidget {
  final String pseudo, phone, email, country;
  final String firstName, lastName, fullName;
  final String? createdAt, birthDate;
  final VoidCallback onAbonnementTap;

  const _ApercuTab({
    required this.pseudo,    required this.phone,
    required this.email,     required this.country,
    required this.firstName, required this.lastName,
    required this.fullName,  required this.createdAt,
    required this.birthDate, required this.onAbonnementTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomNavSpace(context)),
      children: [
        // La carte « Streak & XP » occupait cette place — la meilleure de la
        // page. Elle a été retirée pour deux raisons.
        //
        // D'abord, elle ne servait à rien : l'XP n'était consommé **nulle
        // part**, aucun palier ne débloquait quoi que ce soit, et le streak
        // s'incrémentait à la simple connexion. Elle récompensait l'ouverture
        // de l'application, pas une compétence de l'utilisateur.
        //
        // Ensuite, et surtout : récompenser le retour quotidien dans une
        // application liée aux paris est le motif même que les régulateurs et
        // les relecteurs de stores examinent. Cumulé à la bannière
        // d'affiliation et au parcours promo qui exige un dépôt, l'ensemble se
        // lit comme un dispositif de fidélisation autour de la mise.
        //
        // À la place : le solde de bankroll, la donnée que l'utilisateur vient
        // réellement consulter et qui n'était visible nulle part sur cet écran.
        const _SoldeBankroll(),
        const SizedBox(height: 20),

        // La bande « Actions rapides » a été retirée : ses quatre tuiles
        // dupliquaient toutes un accès déjà présent à l'écran — le crayon de
        // l'avatar, les onglets Abonnement et Parrainage, l'engrenage de
        // l'en-tête — sans ouvrir la moindre destination nouvelle.

        // Stats pronostics (depuis API)
        statsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (stats) {
            // Un taux de réussite n'existe qu'à partir d'un pari tranché. Tant
            // qu'aucun n'est réglé, l'API renvoie 0 — ce 0 était affiché tel
            // quel, en orange, à côté d'une série à 0 en rouge : quelqu'un qui
            // vient de poser son premier pari lisait donc un avertissement et
            // une erreur, alors qu'il n'a simplement pas encore de résultat.
            // `BilanParis` porte la règle, et elle est testée.
            final bilan = BilanParis.depuisApi(stats);
            if (bilan.sansAucunPari) return const SizedBox.shrink();

            final suivis    = bilan.suivis;
            final gagnes    = bilan.gagnes;
            final perdus    = bilan.perdus;
            final serie     = bilan.serie;
            final enAttente = bilan.enAttente;
            final vierge    = bilan.vierge;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _SectionLabel('MES STATS BANKROLL'),
              GestureDetector(
                onTap: () => context.push('/historique'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: context.cl.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.cl.border, width: 0.5)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _StatPill(
                        icon: Icons.savings_rounded,
                        rawValue: suivis.toDouble(),
                        suffix: '',
                        label: 'Paris joués',
                        color: AppColors.primary),
                      Container(height: 32, width: 0.5, color: context.cl.border),
                      _StatPill(
                        icon: Icons.percent_rounded,
                        rawValue: bilan.taux,
                        suffix: '%',
                        label: 'Réussite',
                        color: vierge
                            ? context.cl.textM
                            : (bilan.tauxBrut >= 60
                                ? AppColors.success
                                : AppColors.warning)),
                      Container(height: 32, width: 0.5, color: context.cl.border),
                      _StatPill(
                        icon: Icons.local_fire_department_rounded,
                        rawValue: vierge ? null : serie.toDouble(),
                        suffix: '',
                        label: 'Série en cours',
                        // Une série à zéro n'est pas une faute : c'est une
                        // série qui n'a pas commencé. Le rouge était réservé
                        // aux pertes, il n'a rien à faire ici.
                        color: serie > 0 ? AppColors.success : context.cl.textM),
                    ]),
                    const SizedBox(height: 10),
                    Divider(color: context.cl.border, height: 1),
                    const SizedBox(height: 10),
                    // Aligner « 0 Gagnés / 0 Perdus » sous trois tirets ne dit
                    // rien : le compte est exact mais la raison manque. On
                    // nomme l'état réel — des paris posés, aucun tranché.
                    if (vierge)
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.hourglass_empty_rounded,
                          size: 13, color: context.cl.textM),
                        const SizedBox(width: 6),
                        Flexible(child: Text(
                          enAttente > 1
                            ? '$enAttente paris en attente de résultat'
                            : 'Pari en attente de résultat',
                          style: TextStyle(color: context.cl.textM, fontSize: 12,
                            fontWeight: FontWeight.w600))),
                      ])
                    else
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Row(children: [
                          Container(width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.success, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('$gagnes Gagnés', style: TextStyle(
                            color: AppColors.success, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                        ]),
                        Container(height: 14, width: 0.5, color: context.cl.border),
                        Row(children: [
                          Container(width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('$perdus Perdus', style: TextStyle(
                            color: AppColors.error, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      GestureDetector(
                        onTap: () => context.push('/historique'),
                        child: Row(children: [
                          Text('Historique',
                            style: TextStyle(color: AppColors.primary,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded,
                            color: AppColors.primary, size: 11),
                        ]),
                      ),
                      Container(height: 14, width: 0.5, color: context.cl.border),
                      GestureDetector(
                        onTap: () => context.push('/compte/stats'),
                        child: Row(children: [
                          const Icon(Icons.bar_chart_rounded,
                            color: AppColors.primary, size: 14),
                          const SizedBox(width: 4),
                          const Text('Stats avancées',
                            style: TextStyle(color: AppColors.primary,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded,
                            color: AppColors.primary, size: 11),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
            ]).animate().fadeIn(duration: 350.ms);
          },
        ),

        // Informations
        const _SectionLabel('INFORMATIONS DU COMPTE'),
        _InfoCard(children: [
          // « Prénom » et « Nom » ont été retirés : ils répétaient à la ligne
          // près ce que « Nom complet » affiche déjà juste au-dessus.
          if (fullName.isNotEmpty)
            _InfoRow(label: 'Nom complet',  value: fullName),
          if (birthDate != null)
            _InfoRow(label: 'Date de naissance', value: _formatBirthDate(birthDate!)),
          _InfoRow(label: 'Pseudo',
            value: pseudo.isNotEmpty ? pseudo : ''),
          _InfoRow(label: 'Téléphone',
            value: phone.isNotEmpty ? phone : ''),
          _InfoRow(label: 'Email',
            value: email.isNotEmpty ? email : 'Non renseigné'),
          // Le pays peut légitimement être vide (colonne nullable depuis la
          // suppression du défaut « BF ») : on l'annonce comme pour l'email
          // plutôt que de laisser une ligne blanche.
          _InfoRow(label: 'Pays',
            value: country.isEmpty ? 'Non renseigné' : _countryLabel(context, country)),
          _InfoRow(label: 'Membre depuis',
            value: createdAt != null ? _formatDate(createdAt!) : ''),
        ]),
        const SizedBox(height: 20),

        // Raccourcis, séparés en deux groupes : sept lignes identiques à la
        // suite ne donnaient aucun repère. « Mon activité » regroupe ce qui
        // dépend des paris de l'utilisateur, « Ressources » le reste.
        const _SectionLabel('MON ACTIVITÉ'),
        _InfoCard(children: [
          _LinkRow(icon: Icons.trending_up_rounded, label: 'Pronostics',
            color: AppColors.success, onTap: () => context.go('/pronostics'))
            .animate(delay: 0.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          _LinkRow(icon: Icons.history_rounded, label: 'Historique des résultats',
            color: AppColors.primary, onTap: () => context.push('/historique'))
            .animate(delay: 40.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          _LinkRow(icon: Icons.insights_rounded, label: 'Performance',
            color: const Color(0xFF6C63FF), onTap: () => context.push('/performance'))
            .animate(delay: 45.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          _LinkRow(icon: Icons.emoji_events_rounded, label: 'Classement',
            color: const Color(0xFFFFD700), onTap: () => context.push('/classement'))
            .animate(delay: 50.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
        ]),
        const SizedBox(height: 20),

        const _SectionLabel('RESSOURCES'),
        _InfoCard(children: [
          _LinkRow(icon: Icons.school_rounded, label: 'Tutoriels',
            color: AppColors.info, onTap: () => context.go('/tutoriels'))
            .animate(delay: 100.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          _LinkRow(icon: Icons.people_alt_rounded, label: 'Programme parrainage',
            color: const Color(0xFFA78BFA), onTap: () => context.push('/parrainage'))
            .animate(delay: 140.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          _LinkRow(icon: Icons.notifications_outlined, label: 'Notifications',
            color: AppColors.primary, onTap: () => context.push('/notifications'))
            .animate(delay: 180.ms).fadeIn(duration: 260.ms).slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
        ]),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return iso; }
  }

  String _formatBirthDate(String iso) {
    try {
      final d   = DateTime.parse(iso).toLocal();
      final age = ((DateTime.now().difference(d).inDays) / 365.25).floor();
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} ($age ans)';
    } catch (_) { return iso; }
  }

  /// « BF » → « 🇧🇫 Burkina Faso ». Le profil ne stocke que le code ISO ; on le
  /// résout via la même base que le sélecteur d'indicatif, avec le nom traduit
  /// par `CountryLocalizations`. Un code inconnu est renvoyé tel quel plutôt
  /// que masqué.
  String _countryLabel(BuildContext context, String code) {
    if (code.isEmpty) return '';
    try {
      final c = CountryService().findByCode(code);
      if (c == null) return code;
      final name = CountryLocalizations.of(context)
          ?.countryName(countryCode: c.countryCode) ?? c.name;
      return '${c.flagEmoji}  $name';
    } catch (_) { return code; }
  }
}

// ══════════════════════════════════════════════════════
// ONGLET ABONNEMENT
// ══════════════════════════════════════════════════════
class _AbonnementTab extends ConsumerWidget {
  final bool isPremium;
  const _AbonnementTab({required this.isPremium});

  static const _features = [
    (Icons.star_rounded,          'Pronostics VIP illimités',  'Accès à tous les matchs Premium'),
    (Icons.query_stats_rounded,    'Analyse statistique par match', 'Probabilités et explications détaillées'),
    (Icons.leaderboard_rounded,   'Statistiques avancées',     'Classement et historique complet'),
    (Icons.play_lesson_rounded,   'Tous les tutoriels',        'Bibliothèque complète débloquée'),
    (Icons.headset_mic_rounded,   'Support prioritaire',       'Réponse sous 2h ouvrées'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(currentSubscriptionProvider);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomNavSpace(context)),
      children: [
        subAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error:   (_, _) => const SizedBox.shrink(),
          data: (sub) {
            final daysLeft     = (sub['days_left'] as num?)?.toInt() ?? 0;
            final pendingProof = sub['pending_proof'];

            if (isPremium) {
              return _PremiumState(
                daysLeft: daysLeft, sub: sub, features: _features);
            }
            if (pendingProof != null) return _PendingState(features: _features);
            return _FreeState(sub: sub, features: _features);
          },
        ),
      ],
    );
  }
}

// ── État GRATUIT ──────────────────────────────────────────────────────────────
class _FreeState extends ConsumerWidget {
  final Map<String, dynamic> sub;
  final List<(IconData, String, String)> features;
  const _FreeState({required this.sub, required this.features});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Plan actuel
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cl.border, width: 0.5)),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.person_rounded, color: context.cl.textM, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Plan Gratuit', style: TextStyle(
              color: context.cl.textP, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Accès limité aux pronostics', style: TextStyle(
              color: context.cl.textM, fontSize: 11)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.cl.surfaceDeep,
              borderRadius: BorderRadius.circular(8)),
            child: Text('Gratuit', style: TextStyle(
              color: context.cl.textS, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),

      const SizedBox(height: 20),

      // CTA premium attractif
      GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          goToPremium(context, ref, extra: sub);
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1206), Color(0xFF2D1F0A), Color(0xFF1A1206)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.4), width: 1)),
          child: Column(children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Passer à Premium', style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Débloquez tout PronoWin', style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(premiumMonthlyPriceLabel(ref, sub), style: const TextStyle(
                  color: AppColors.primaryLight, fontSize: 22, fontWeight: FontWeight.w900)),
                const Text('/mois', style: TextStyle(
                  color: Colors.white54, fontSize: 10)),
              ]),
            ]),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 12, offset: const Offset(0, 4))]),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Activer maintenant', style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ]),
            ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(reverse: true); })
              .shimmer(duration: 2000.ms, color: Colors.white10, delay: 800.ms),
          ]),
        ),
      ).animate(delay: 60.ms).fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

      const SizedBox(height: 24),

      // Titre section fonctionnalités
      Row(children: [
        Text('CE QUE VOUS DÉBLOQUEZ', style: TextStyle(
          color: context.cl.textM, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6)),
          child: const Text('5 avantages', style: TextStyle(
            color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600))),
      ]).animate(delay: 100.ms).fadeIn(duration: 280.ms),

      const SizedBox(height: 10),

      // Features lockées
      ...features.asMap().entries.map((e) {
        final (icon, label, sub) = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: AppColors.primary.withValues(alpha: 0.5), size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(
                  color: context.cl.textS, fontSize: 13,
                  fontWeight: FontWeight.w600)),
                Text(sub, style: TextStyle(
                  color: context.cl.textM, fontSize: 11)),
              ])),
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: context.cl.surfaceDeep,
                  shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded,
                  color: context.cl.textM, size: 12)),
            ]),
          ).animate(delay: Duration(milliseconds: 120 + e.key * 50))
            .fadeIn(duration: 280.ms).slideX(begin: 0.03, end: 0),
        );
      }),
    ]);
  }
}

// ── État EN ATTENTE ───────────────────────────────────────────────────────────
class _PendingState extends StatelessWidget {
  final List<(IconData, String, String)> features;
  const _PendingState({required this.features});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PendingBanner(),
      const SizedBox(height: 16),
      ...features.map((f) {
        final (icon, label, sub) = f;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.border, width: 0.5)),
            child: Row(children: [
              Icon(icon, color: AppColors.warning.withValues(alpha: 0.6), size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(
                color: context.cl.textS, fontSize: 13, fontWeight: FontWeight.w600))),
              const Icon(Icons.hourglass_top_rounded,
                color: AppColors.warning, size: 16),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── État PREMIUM ──────────────────────────────────────────────────────────────
class _PremiumState extends ConsumerWidget {
  final int daysLeft;
  final Map<String, dynamic> sub;
  final List<(IconData, String, String)> features;
  const _PremiumState({
    required this.daysLeft, required this.sub, required this.features});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiresoon = daysLeft > 0 && daysLeft <= 7;
    // Le bandeau apparaît dès 30 jours : à 7 jours il ne reste plus beaucoup de
    // marge pour un paiement Mobile Money validé manuellement sous 30 min.
    final renewable  = daysLeft > 0 && daysLeft <= 30;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Carte Premium active
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2040), Color(0xFF0D1530)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4), width: 1),
          boxShadow: [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 20, offset: const Offset(0, 6))]),
        child: Column(children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight]),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plan Premium Actif', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              Text(
                daysLeft > 0
                  ? 'Expire dans $daysLeft jour${daysLeft > 1 ? 's' : ''}'
                  : 'Actif sans limite',
                style: TextStyle(
                  color: expiresoon ? AppColors.warning : AppColors.success,
                  fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3))),
              child: const Text('Actif', style: TextStyle(
                color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700))),
          ]),
          // Ce bandeau était purement décoratif : il annonçait l'expiration
          // sans offrir le moindre moyen de renouveler. L'onglet Abonnement
          // étant le seul écran où un abonné voit sa date de fin, il n'avait
          // aucun chemin vers le paiement depuis là.
          if (renewable) ...[
            const SizedBox(height: 14),
            Builder(builder: (_) {
              final color = expiresoon ? AppColors.warning : AppColors.info;
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.25))),
                child: Row(children: [
                  Icon(
                    expiresoon
                      ? Icons.warning_amber_rounded
                      : Icons.refresh_rounded,
                    color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    expiresoon
                      ? 'Renouvellement recommandé'
                      : 'Prolonge sans interruption',
                    style: TextStyle(color: color, fontSize: 12,
                      fontWeight: FontWeight.w600))),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      goToPremium(context, ref, extra: sub);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Renouveler', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700))),
                ]));
            }),
          ],
        ]),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),

      const SizedBox(height: 24),

      Row(children: [
        Text('VOS AVANTAGES', style: TextStyle(
          color: context.cl.textM, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6)),
          child: const Text('Tout débloqué ✓', style: TextStyle(
            color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w600))),
      ]).animate(delay: 80.ms).fadeIn(duration: 280.ms),

      const SizedBox(height: 10),

      ...features.asMap().entries.map((e) {
        final (icon, label, sub) = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.15), width: 0.5)),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: AppColors.success, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(
                  color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(sub, style: TextStyle(
                  color: context.cl.textS, fontSize: 11)),
              ])),
              const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 18),
            ]),
          ).animate(delay: Duration(milliseconds: 100 + e.key * 50))
            .fadeIn(duration: 280.ms).slideX(begin: 0.03, end: 0),
        );
      }),
    ]);
  }
}

// ══════════════════════════════════════════════════════
// ONGLET PARRAINAGE
// ══════════════════════════════════════════════════════
class _ParrainageTab extends ConsumerWidget {
  final String refCode;
  final int    earnings;
  const _ParrainageTab({required this.refCode, required this.earnings});

  static const _purple = Color(0xFFA78BFA);

  /// Message pré-rédigé, identique à celui de ParrainagePage : l'utilisateur
  /// n'a plus à composer son propre texte ni à copier-coller le code.
  static String _shareMessage(String code) =>
      '🏆 Rejoins PronoWin et gagne avec les meilleurs pronostics !\n'
      'Utilise mon code de parrainage : *$code*\n'
      '👉 Télécharge l\'app : pronowin.com/download\n'
      '💰 Tu m\'aides aussi à gagner des commissions !';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refAsync = ref.watch(referralStatsProvider);
    final stats    = refAsync.valueOrNull ?? const <String, dynamic>{};

    // Barème lu depuis l'API (REFERRAL_COMMISSION_L1/L2 et REFERRAL_MIN_WITHDRAWAL
    // côté backend) plutôt que codé en dur : il est pilotable par variable
    // d'environnement, l'écran doit suivre.
    final comL1 = (stats['commission_l1']  as num?)?.toInt() ?? 500;
    final comL2 = (stats['commission_l2']  as num?)?.toInt() ?? 200;
    // Devise du versement, publiee par le serveur a cote des montants.
    //
    // Cet ecran ecrivait le libelle de memoire, et pas deux fois pareil :
    // le solde en « FCFA », les commissions en « F », a quatre centimetres
    // d'ecart. Ce n'est pas la devise du Bankroll — c'est celle du virement
    // Mobile Money que nous emettons.
    final devise = nomDevise(stats['currency'] as String? ?? 'XOF');
    final minW  = (stats['min_withdrawal'] as num?)?.toInt() ?? 2000;
    final canW  = stats['can_withdraw'] as bool? ?? false;

    final s  = stats['stats'] as Map<String, dynamic>? ?? const {};
    final l1 = (s['total_l1']   as num?)?.toInt() ?? 0;
    final l2 = (s['total_l2']   as num?)?.toInt() ?? 0;
    final p1 = (s['premium_l1'] as num?)?.toInt() ?? 0;
    final aucunFilleul = l1 == 0 && l2 == 0;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomNavSpace(context)),
      children: [
        // ── Gains + progression vers le seuil de retrait ────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1040), Color(0xFF0D0820)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _purple.withValues(alpha: 0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet_rounded,
                color: _purple, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mes gains parrainage',
                    style: TextStyle(color: context.cl.textS, fontSize: 12)),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: earnings),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text('$v $devise', style: const TextStyle(
                      color: _purple, fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            // Le seuil de retrait n'apparaissait nulle part : on voyait « 0 FCFA »
            // sans savoir à partir de quel montant on peut être payé.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: minW > 0 ? (earnings / minW).clamp(0.0, 1.0) : 0,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(_purple)),
            ),
            const SizedBox(height: 7),
            Text(
              canW
                ? 'Seuil atteint — tu peux demander ton retrait.'
                : '$earnings / $minW FCFA avant de pouvoir retirer',
              style: TextStyle(
                color: canW ? AppColors.success : context.cl.textM,
                fontSize: 11.5,
                fontWeight: canW ? FontWeight.w600 : FontWeight.w400)),
            if (canW) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 42,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/parrainage/retrait',
                    extra: {'earnings': earnings, 'min': minW}),
                  icon: const Icon(Icons.payments_rounded, size: 17),
                  label: const Text('Retirer mes gains'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11))))),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // ── Barème : l'information la plus importante, absente jusqu'ici ────
        const _SectionLabel('CE QUE ÇA TE RAPPORTE'),
        Row(children: [
          Expanded(child: _RewardTile(
            amount: '$comL1 $devise', label: 'par filleul direct', color: _purple)),
          const SizedBox(width: 10),
          Expanded(child: _RewardTile(
            amount: '$comL2 $devise', label: 'par filleul indirect', color: AppColors.info)),
        ]),
        const SizedBox(height: 16),

        // ── Comment ça marche ───────────────────────────────────────────────
        const _SectionLabel('COMMENT ÇA MARCHE'),
        _InfoCard(children: [
          _HowToStep(n: 1, text: 'Partage ton code avec tes amis'),
          _HowToStep(n: 2, text: 'Ils créent leur compte avec ce code'),
          _HowToStep(n: 3,
            text: 'Tu gagnes $comL1 $devise dès qu\'ils passent Premium', last: true),
        ]),
        const SizedBox(height: 16),

        // ── Code + partage ──────────────────────────────────────────────────
        const _SectionLabel('MON CODE'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: context.cl.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cl.border, width: 0.5)),
          child: Row(children: [
            Text(refCode, style: const TextStyle(
              color: _purple, fontSize: 22,
              fontWeight: FontWeight.w800, letterSpacing: 4)),
            const Spacer(),
            IconButton(
              tooltip: 'Copier le code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: refCode));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Code copié'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 2)));
              },
              icon: const Icon(Icons.copy_rounded, color: _purple, size: 20)),
          ]),
        ),
        const SizedBox(height: 12),
        // Le partage devient l'action principale : copier le code obligeait
        // l'utilisateur à rédiger lui-même son message.
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              Share.share(_shareMessage(refCode));
            },
            icon: const Icon(Icons.share_rounded, size: 19),
            label: const Text('Partager mon code',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13))))),
        const SizedBox(height: 20),

        // ── Filleuls ────────────────────────────────────────────────────────
        if (aucunFilleul)
          // Deux compteurs à zéro n'apprennent rien : on remplace par une
          // amorce qui explique ce qu'il se passera.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
            decoration: BoxDecoration(
              color: context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cl.borderSoft, width: 0.8)),
            child: Column(children: [
              Icon(Icons.group_add_rounded, color: _purple.withValues(alpha: 0.7), size: 34),
              const SizedBox(height: 12),
              Text('Aucun filleul pour le moment',
                style: TextStyle(
                  color: context.cl.textP, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Partage ton code : chaque ami qui s\'abonne te rapporte '
                '$comL1 $devise, et ceux qu\'il parraine à son tour $comL2 $devise.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cl.textM, fontSize: 12.5, height: 1.45)),
            ]),
          )
        else ...[
          Row(children: [
            _StatBox(label: 'Filleuls directs',
              value: '$l1', sub: '$p1 Premium', color: _purple),
            const SizedBox(width: 10),
            _StatBox(label: 'Filleuls indirects',
              value: '$l2', sub: '$comL2 $devise / filleul', color: AppColors.info),
          ]).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/parrainage'),
              icon: const Icon(Icons.people_rounded, size: 18),
              label: const Text('Voir le détail de mes filleuls'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _purple,
                side: const BorderSide(color: _purple, width: 1)))),
        ],
      ],
    );
  }
}

// ─── Widgets réutilisables ────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label; final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(
      color: color, fontSize: 11, fontWeight: FontWeight.w600)));
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 11,
      fontWeight: FontWeight.w600, letterSpacing: 1)));
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: context.cl.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.cl.border, width: 0.5)),
    child: Column(children: children));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.cl.border, width: 0.3))),
    child: Row(children: [
      Text(label, style: TextStyle(color: context.cl.textM, fontSize: 13)),
      const Spacer(),
      Text(value, style: TextStyle(
        color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w500)),
    ]));
}

class _LinkRow extends StatelessWidget {
  final IconData icon; final Color color;
  final String label; final VoidCallback onTap;
  const _LinkRow({required this.icon, required this.color,
    required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        Icon(Icons.chevron_right_rounded, color: context.cl.textM, size: 18),
      ])));
}

class _PendingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3))),
    child: const Row(children: [
      Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 18),
      SizedBox(width: 8),
      Text('Preuve en cours de vérification',
        style: TextStyle(color: AppColors.warning,
          fontSize: 13, fontWeight: FontWeight.w500)),
    ]));
}

// _FeatureRow remplacé par _FreeState/_PremiumState inline

// ─── Stat pill dans section stats ────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  /// [rawValue] vaut `null` quand la mesure n'a pas de sens faute de données —
  /// un taux de réussite sans pari tranché, par exemple. On affiche alors un
  /// tiret : compter zéro et ne rien savoir sont deux choses différentes, et
  /// afficher « 0 % » à la place d'un tiret revient à annoncer un échec qui
  /// n'a pas eu lieu.
  final IconData icon; final double? rawValue; final String suffix, label; final Color color;
  const _StatPill({required this.icon, required this.rawValue, required this.suffix,
    required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final v = rawValue;
    return Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      if (v == null)
        // Pas de compteur animé : il partirait de 0 pour arriver à 0, ce qui
        // laisserait croire à une valeur mesurée.
        Text('—', style: TextStyle(
          color: color, fontSize: 15, fontWeight: FontWeight.w800))
      else
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, x, _) => Text('${x.toStringAsFixed(0)}$suffix',
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        color: context.cl.textM, fontSize: 10)),
    ]);
  }
}

// ─── AVATAR PROFIL AVEC BADGE NIVEAU ─────────────────────────────────────────
class _ProfileAvatar extends StatelessWidget {
  final String initiale;
  final String? avatarUrl;
  final bool isPremium;
  final int earnings;
  final VoidCallback onEdit;

  const _ProfileAvatar({
    required this.initiale,
    this.avatarUrl,
    required this.isPremium,
    required this.earnings,
    required this.onEdit,
  });

  _LevelData get _level {
    if (earnings >= 50000) return _LevelData('💎', 'Diamant', const Color(0xFF67E8F9));
    if (earnings >= 20000) return _LevelData('🥇', 'Or',      const Color(0xFFFFD700));
    if (earnings >= 5000)  return _LevelData('🥈', 'Argent',  const Color(0xFFCBD5E1));
    return _LevelData('🥉', 'Bronze', const Color(0xFFCD7F32));
  }

  @override
  Widget build(BuildContext context) {
    final lv = _level;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [lv.color, lv.color.withValues(alpha: 0.2), lv.color])),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: context.cl.bg),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                ? ImageDistante(
                    url:   avatarUrl,
                    repli: Center(child: Text(initiale,
                      style: const TextStyle(color: Colors.white,
                        fontSize: 28, fontWeight: FontWeight.w800))))
                : Center(child: Text(initiale,
                    style: const TextStyle(color: Colors.white,
                      fontSize: 28, fontWeight: FontWeight.w800))),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -4, right: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: lv.color.withValues(alpha: 0.6), width: 1)),
          child: Text('${lv.emoji} ${lv.name}',
            style: TextStyle(color: lv.color,
              fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ),
      Positioned(
        top: -2, right: -6,
        child: Semantics(
          label: 'Modifier la photo de profil',
          button: true,
          child: GestureDetector(
            onTap: onEdit,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle,
                border: Border.all(color: context.cl.bg, width: 2)),
              child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14)),
          ),
        ),
      ),
    ]);
  }
}

class _LevelData {
  final String emoji, name;
  final Color color;
  const _LevelData(this.emoji, this.name, this.color);
}

// ─── BADGE PREMIUM ANIMÉ ──────────────────────────────────────────────────────
class _PremiumBadge extends StatefulWidget {
  final bool isPremium;
  const _PremiumBadge({required this.isPremium});
  @override
  State<_PremiumBadge> createState() => _PremiumBadgeState();
}

class _PremiumBadgeState extends State<_PremiumBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));
    _shimmer = Tween<double>(begin: -1.5, end: 2.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Boucle infinie : coupée si l'utilisateur a réduit les animations.
    // Ce hook est aussi rappelé quand le réglage système change.
    context.boucler(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: context.cl.textM.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20)),
        child: Text('Gratuit', style: TextStyle(
          color: context.cl.textM, fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_shimmer.value - 0.5, 0),
            end: Alignment(_shimmer.value + 0.5, 0),
            colors: const [
              Color(0xFFB8860B), Color(0xFFFFD700),
              Color(0xFFDAA520), Color(0xFFFFD700), Color(0xFFB8860B),
            ],
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
            blurRadius: 10)]),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text('PREMIUM', style: TextStyle(
            color: Colors.white, fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

// ─── STATS PROFIL (header) ────────────────────────────────────────────────────
/// Montant du barème de parrainage — le chiffre d'abord, le libellé ensuite.
class _RewardTile extends StatelessWidget {
  final String amount, label;
  final Color color;
  const _RewardTile({required this.amount, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(amount, style: TextStyle(
        color: color, fontSize: 20, fontWeight: FontWeight.w800, height: 1)),
      const SizedBox(height: 5),
      Text(label,
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.cl.textM, fontSize: 11.5, height: 1.3)),
    ]),
  );
}

/// Une étape numérotée de « Comment ça marche ».
class _HowToStep extends StatelessWidget {
  final int n;
  final String text;
  final bool last;
  const _HowToStep({required this.n, required this.text, this.last = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(14, 12, 14, last ? 12 : 0),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
          shape: BoxShape.circle),
        child: Text('$n', style: const TextStyle(
          color: Color(0xFFA78BFA), fontSize: 11.5, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Text(text, style: TextStyle(
          color: context.cl.textS, fontSize: 13, height: 1.4))),
    ]),
  );
}

class _StatBox extends StatelessWidget {
  final String label, value, sub; final Color color;
  const _StatBox({required this.label, required this.value,
    required this.sub, required this.color});
  @override
  Widget build(BuildContext context) {
    final rawInt = int.tryParse(value) ?? 0;
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: context.cl.textM, fontSize: 11)),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: rawInt),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text('$v', style: TextStyle(
            color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        Text(sub, style: TextStyle(color: context.cl.textM, fontSize: 10)),
      ])));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STREAK CARD (compte page)
// ══════════════════════════════════════════════════════════════════════════════
/// Solde de bankroll — ce que l'utilisateur vient consulter.
///
/// Remplace la carte « Streak & XP », qui occupait la meilleure place de la
/// page sans rien apporter : l'XP n'etait consomme nulle part, aucun palier ne
/// debloquait quoi que ce soit, et le streak s'incrementait a la connexion.
///
/// Le solde, lui, existait deja cote serveur et n'apparaissait sur aucun ecran
/// de cette page — seules les statistiques de paris y figuraient, sans jamais
/// dire combien il reste.
class _SoldeBankroll extends ConsumerWidget {
  const _SoldeBankroll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bankrollProvider);
    final data  = async.valueOrNull;

    // Aucune bankroll configuree : on invite plutot que d'afficher un zero,
    // qui se lirait comme un solde epuise.
    if (data == null) {
      return _CarteCompte(
        onTap: () => context.push('/bankroll'),
        enfant: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.savings_rounded,
              color: AppColors.primary, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suivre ma bankroll', style: TextStyle(
                color: context.cl.textP, fontSize: 15,
                fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Definis ton budget et suis tes gains reels',
                style: TextStyle(color: context.cl.textM, fontSize: 12)),
            ])),
          Icon(Icons.chevron_right_rounded, color: context.cl.textM, size: 20),
        ]),
      );
    }

    final devise  = nomDevise(data.currency);
    final ecart   = data.currentBalance - data.totalBudget;
    // Un ecart nul n'est ni un gain ni une perte : aucune couleur, aucun signe.
    final neutre  = ecart.abs() < 0.5;
    final couleur = neutre
        ? context.cl.textM
        : (ecart > 0 ? AppColors.success : AppColors.error);

    return _CarteCompte(
      onTap: () => context.push('/bankroll'),
      enfant: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SOLDE ACTUEL', style: TextStyle(
              color: context.cl.textM, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text('${montantExact(data.currentBalance)} $devise',
              style: TextStyle(
                color: context.cl.textP, fontSize: 26,
                fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text(
              neutre
                ? 'Budget de départ : ${montantExact(data.totalBudget)} $devise'
                : '${montantSigne(ecart)} $devise depuis le départ',
              style: TextStyle(
                color: couleur, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ])),
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.savings_rounded,
            color: AppColors.primary, size: 22)),
      ]),
    );
  }
}

/// Cadre commun aux cartes de la page Compte.
class _CarteCompte extends StatelessWidget {
  final Widget enfant;
  final VoidCallback onTap;
  const _CarteCompte({required this.enfant, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.borderSoft, width: 0.8)),
      child: enfant,
    ),
  );
}
