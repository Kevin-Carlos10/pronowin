import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  bool _navVisible = true;

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

  static const _navItems = [
    _NavItemData(icon: Icons.home_rounded,                      label: 'Accueil'),
    _NavItemData(icon: Icons.trending_up_rounded,               label: 'Pronos'),
    _NavItemData(icon: Icons.account_balance_wallet_rounded,    label: 'Bankroll'),
    _NavItemData(icon: Icons.play_circle_outline_rounded,       label: 'Tutoriels'),
    _NavItemData(icon: Icons.person_rounded,                    label: 'Compte'),
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
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              // Rétrécit la barre au scroll vers le bas (plus de place pour le
              // contenu), la ramène à sa taille normale au scroll vers le haut
              // — les notifications de scroll remontent naturellement depuis
              // n'importe quelle liste de la page active, pas besoin d'y toucher.
              onNotification: (notification) {
                if (notification.direction == ScrollDirection.reverse) {
                  if (_navVisible) setState(() => _navVisible = false);
                } else if (notification.direction == ScrollDirection.forward) {
                  if (!_navVisible) setState(() => _navVisible = true);
                }
                return false;
              },
              child: IndexedStack(index: _currentIndex, children: _pages(loggedIn)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        scale: _navVisible ? 1.0 : 0.82,
        child: _FloatingNavBar(
          currentIndex: _currentIndex,
          items: _navItems,
          iconScales: _iconScales,
          bottomPadding: bottomPadding,
          onTap: _onTap,
        ),
      ),
    );
  }
}

// ─── DATA ─────────────────────────────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

// ─── FLOATING NAV BAR ─────────────────────────────────────────────────────────
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 0, 12, bottomPadding + BottomNavMetrics.margeBasse),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: BottomNavMetrics.hauteur,
            decoration: BoxDecoration(
              color: context.cl.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: context.cl.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final item = items[i];
                final sel = i == currentIndex;

                return _NavItemWidget(
                  item: item,
                  isSelected: sel,
                  scale: iconScales[i],
                  onTap: () => onTap(i),
                );
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
    return Semantics(
      label:    item.label,
      selected: isSelected,
      button:   true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: scale,
                  builder: (_, child) => Transform.scale(
                    scale: scale.value,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: isSelected ? 40 : 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      item.icon,
                      color: isSelected ? AppColors.primary : context.cl.textM,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : context.cl.textM,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  child: Text(item.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

