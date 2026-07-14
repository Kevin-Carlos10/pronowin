import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DURÉES
// ═══════════════════════════════════════════════════════════════════════════
const _kFastDuration   = Duration(milliseconds: 220);
const _kNormalDuration = Duration(milliseconds: 300);
const _kModalDuration  = Duration(milliseconds: 340);

// ═══════════════════════════════════════════════════════════════════════════
// SLIDE FROM RIGHT  (navigation standard vers une sous-page)
// ═══════════════════════════════════════════════════════════════════════════
CustomTransitionPage<T> slideRightPage<T>({
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key:                state.pageKey,
      child:              child,
      transitionDuration: _kNormalDuration,
      reverseTransitionDuration: _kFastDuration,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final slide = CurvedAnimation(
          parent: animation, curve: Curves.easeOutCubic);
        final fadeOut = CurvedAnimation(
          parent: secondaryAnimation, curve: Curves.easeIn);

        return SlideTransition(
          position: Tween(
            begin: const Offset(1.0, 0.0),
            end:   Offset.zero,
          ).animate(slide),
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.92).animate(fadeOut),
            child: child,
          ),
        );
      },
    );

// ═══════════════════════════════════════════════════════════════════════════
// SLIDE UP MODAL  (pages détail — carte → détail match/tutoriel)
// ═══════════════════════════════════════════════════════════════════════════
CustomTransitionPage<T> slideUpPage<T>({
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key:                state.pageKey,
      child:              child,
      transitionDuration: _kModalDuration,
      reverseTransitionDuration: _kFastDuration,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation, curve: Curves.easeOutCubic);

        return SlideTransition(
          position: Tween(
            begin: const Offset(0.0, 0.06),
            end:   Offset.zero,
          ).animate(curve),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
    );

// ═══════════════════════════════════════════════════════════════════════════
// FADE  (auth, redirection, lock screen)
// ═══════════════════════════════════════════════════════════════════════════
CustomTransitionPage<T> fadePage<T>({
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key:                state.pageKey,
      child:              child,
      transitionDuration: _kFastDuration,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child:   child,
      ),
    );

// ═══════════════════════════════════════════════════════════════════════════
// SCALE + FADE  (modales premium, paywall)
// ═══════════════════════════════════════════════════════════════════════════
CustomTransitionPage<T> scaleUpPage<T>({
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key:                state.pageKey,
      child:              child,
      transitionDuration: _kModalDuration,
      reverseTransitionDuration: _kFastDuration,
      transitionsBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(
          parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curve),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
    );
