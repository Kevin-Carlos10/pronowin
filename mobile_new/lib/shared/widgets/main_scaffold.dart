import 'package:pronowin/l10n/app_strings.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../features/accueil/presentation/pages/accueil_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/pronostics/presentation/pages/pronostics_page.dart';
import '../../features/bankroll/presentation/pages/bankroll_page.dart';
import '../../features/tutoriels/presentation/pages/tutoriels_page.dart';
import '../../features/compte/presentation/pages/compte_page.dart';
import 'bottom_nav_metrics.dart';
import 'pile_onglets_paresseuse.dart';
import 'guest_locked_view.dart';
import 'offline_banner.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final int initialIndex;
  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late List<AnimationController> _iconControllers;
  late List<Animation<double>> _iconScales;

  static const _guestPages = {
    2: GuestLockedView(
      icon:    Icons.account_balance_wallet_rounded,
      title:   'Suis ta bankroll',
      message: 'Connecte-toi pour enregistrer tes mises, suivre ton budget '
                'et ta rentabilité à chaque résultat.',
      from:    '/bankroll',
    ),
    4: GuestLockedView(
      icon:    Icons.person_rounded,
      title:   'Ton compte PronoWin',
      message: 'Connecte-toi pour accéder à ton profil, ton abonnement '
                'Premium et ton programme de parrainage.',
      from:    '/compte',
      // Le routeur autorise déjà /parametres (et ses pages légales) en mode
      // invité — inutile de forcer une connexion juste pour les atteindre.
      secondaryLabel: 'Paramètres, mentions légales…',
      secondaryRoute: '/parametres',
    ),
  };

  List<Widget> _pages(bool loggedIn) => [
    const AccueilPage(),
    const PronosticsPage(),
    loggedIn ? const BankrollPage() : _guestPages[2]!,
    const TutorielsPage(),
    loggedIn ? const ComptePage()  : _guestPages[4]!,
  ];

  // Au trait au repos, pleine quand l'onglet est ouvert — comme Instagram.
  // Le ballon remplace la courbe de « Pronos » : sans libellé, l'icône doit
  // dire seule de quoi parle l'onglet.
  static const _navItems = [
    _NavItemData(icon: Icons.home_outlined,                   active: Icons.home_rounded,                   label: 'Accueil'),
    _NavItemData(icon: Icons.sports_soccer_outlined,          active: Icons.sports_soccer,                  label: 'Pronos'),
    _NavItemData(icon: Icons.account_balance_wallet_outlined, active: Icons.account_balance_wallet_rounded, label: 'Bankroll'),
    _NavItemData(icon: Icons.play_circle_outline_rounded,     active: Icons.play_circle_rounded,            label: 'Tutoriels'),
    _NavItemData(icon: Icons.account_circle_outlined,         active: Icons.account_circle,                 label: 'Compte'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _iconControllers = List.generate(
      _navItems.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
      ),
    );
    _iconScales = _iconControllers
        .map((c) => Tween<double>(begin: 1.0, end: 1.25).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOutBack),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _iconControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTap(int i) {
    if (i == _currentIndex) return;
    HapticFeedback.lightImpact();
    _iconControllers[i].forward().then((_) => _iconControllers[i].reverse());
    setState(() => _currentIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final loggedIn       = ref.watch(effectiveLoggedInProvider);

    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          const OfflineBanner(),
          // La barre ne réagit plus au défilement, et le mécanisme qui le
          // faisait est retiré plutôt que débranché : un `NotificationListener`
          // qui n'alimente qu'un champ que personne ne lit se remet en service
          // tout seul le jour où quelqu'un le croit encore utile.
          Expanded(
            child: PileOngletsParesseuse(
              index:    _currentIndex,
              children: _pages(loggedIn),
            ),
          ),
        ],
      ),
      // La barre garde sa taille, quoi qu'il arrive au défilement.
      //
      // Elle tombait à 82 % au scroll vers le bas, pour « laisser plus de
      // place au contenu ». Le gain réel est d'une dizaine de pixels ; le coût
      // était un libellé de 10 px lu autour de 8, et des cibles amputées de
      // près d'un cinquième de leur surface — au moment précis où l'on
      // parcourt une liste, et donc où l'on peut vouloir changer d'onglet.
      //
      // Un élément de navigation est soit pleinement utilisable, soit absent.
      // Entre les deux, il occupe la place sans se laisser atteindre.
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        items: _navItems,
        iconScales: _iconScales,
        bottomPadding: bottomPadding,
        onTap: _onTap,
      ),
    );
  }
}

/// La barre seule, pour les bancs de mise en page : la monter dans
/// [MainScaffold] chargerait les cinq onglets.
@visibleForTesting
Widget barreNavigationSeule({int index = 0}) => _FloatingNavBar(
      currentIndex: index,
      items: _MainScaffoldState._navItems,
      iconScales: List.filled(5, const AlwaysStoppedAnimation<double>(1)),
      bottomPadding: 0,
      onTap: (_) {},
    );

// ─── DATA ─────────────────────────────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final IconData active;
  final String label;
  const _NavItemData({required this.icon, required this.active, required this.label});
}

// ─── FLOATING NAV BAR ─────────────────────────────────────────────────────────
/// La barre façon Instagram : une capsule flottante, translucide, des icônes
/// sans libellé ; l'onglet ouvert a son icône pleine, posée sur une pastille
/// grise qui glisse d'un onglet à l'autre.
///
/// Sans libellé, chaque case garde son nom pour les lecteurs d'écran
/// (`Semantics`), et l'affiche sur un appui long (`Tooltip`).
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final List<_NavItemData> items;
  final List<Animation<double>> iconScales;
  final double bottomPadding;
  final void Function(int) onTap;

  const _FloatingNavBar({
    required this.currentIndex,
    required this.items,
    required this.iconScales,
    required this.bottomPadding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sombre = context.isDark;
    final contraste = sombre ? Colors.white : Colors.black;
    final hauteur = BottomNavMetrics.hauteur(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, bottomPadding + BottomNavMetrics.margeBasse),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: sombre ? 0.45 : 0.10),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(hauteur / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: hauteur,
              padding: const EdgeInsets.all(5),
              decoration: ShapeDecoration(
                color: (sombre ? const Color(0xFF1C1F26) : Colors.white)
                    .withValues(alpha: 0.92),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: contraste.withValues(alpha: sombre ? 0.10 : 0.08),
                    width: 0.6,
                  ),
                ),
              ),
              // Cinq cases qui se partagent la largeur, la pastille de
              // l'onglet ouvert glissant derrière elles.
              child: LayoutBuilder(builder: (context, contraintes) {
                final largeur = contraintes.maxWidth / items.length;
                return Stack(children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: largeur * currentIndex,
                    top: 0,
                    bottom: 0,
                    width: largeur,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        color: contraste.withValues(alpha: sombre ? 0.14 : 0.08),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(items.length, (i) => Expanded(
                      child: _NavItemWidget(
                        item: items[i],
                        isSelected: i == currentIndex,
                        scale: iconScales[i],
                        onTap: () => onTap(i),
                      ),
                    )),
                  ),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── NAV ITEM ─────────────────────────────────────────────────────────────────
class _NavItemWidget extends StatelessWidget {
  final _NavItemData item;
  final bool isSelected;
  final Animation<double> scale;
  final VoidCallback onTap;

  const _NavItemWidget({
    required this.item,
    required this.isSelected,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nom = tr(context, item.label);
    return Semantics(
      label:    nom,
      selected: isSelected,
      button:   true,
      child: Tooltip(
        message: nom,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ExcludeSemantics(
            child: Center(
              child: AnimatedBuilder(
                animation: scale,
                builder: (_, child) => Transform.scale(scale: scale.value, child: child),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    isSelected ? item.active : item.icon,
                    key: ValueKey(isSelected),
                    color: context.cl.textP,
                    size: BottomNavMetrics.tailleIcone,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
