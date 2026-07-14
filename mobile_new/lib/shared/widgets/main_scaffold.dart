import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../features/accueil/presentation/pages/accueil_page.dart';
import '../../features/pronostics/presentation/pages/pronostics_page.dart';
import '../../features/bankroll/presentation/pages/bankroll_page.dart';
import '../../features/tutoriels/presentation/pages/tutoriels_page.dart';
import '../../features/compte/presentation/pages/compte_page.dart';
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

  static const _pages = [
    AccueilPage(),
    PronosticsPage(),
    BankrollPage(),
    TutorielsPage(),
    ComptePage(),
  ];

  static const _navItems = [
    _NavItemData(icon: Icons.home_rounded,                      label: 'Accueil'),
    _NavItemData(icon: Icons.trending_up_rounded,               label: 'Pronos'),
    _NavItemData(icon: Icons.account_balance_wallet_rounded,    label: 'Bankroll', isCentral: true),
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

    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: IndexedStack(index: _currentIndex, children: _pages)),
        ],
      ),
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

// ─── DATA ─────────────────────────────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final String label;
  final bool isCentral;
  const _NavItemData({required this.icon, required this.label, this.isCentral = false});
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
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: context.cl.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(28),
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

                if (item.isCentral) {
                  return _CentralButton(
                    icon: item.icon,
                    scale: iconScales[i],
                    onTap: () => onTap(i),
                    isSelected: sel,
                  );
                }

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

// ─── BOUTON CENTRAL ───────────────────────────────────────────────────────────
class _CentralButton extends StatelessWidget {
  final IconData icon;
  final Animation<double> scale;
  final VoidCallback onTap;
  final bool isSelected;

  const _CentralButton({
    required this.icon,
    required this.scale,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:  'Bankroll',
      button: true,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: scale,
        builder: (_, child) => Transform.scale(scale: scale.value, child: child),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.success, Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ExcludeSemantics(
            child: Icon(icon, color: Colors.white, size: 24)),
        ),
      ),
    ));
  }
}
