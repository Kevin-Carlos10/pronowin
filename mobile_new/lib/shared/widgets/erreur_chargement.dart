import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../utils/premium_nav.dart';

/// Écran d'erreur qui distingue *pourquoi* le chargement a échoué.
///
/// Ce composant existe parce que la même faute est apparue trois fois dans
/// l'application : un écran affichait « Vérifie ta connexion » à un utilisateur
/// dont la connexion allait parfaitement bien, mais qui n'avait simplement pas
/// de compte. Le bouton « Réessayer » relançait alors le même 401 à l'infini.
///
/// Trois causes, trois messages, trois actions :
///
/// | Code | Cause                | Action proposée      |
/// |------|----------------------|----------------------|
/// | 401  | pas de compte        | créer un compte      |
/// | 403  | compte non Premium   | découvrir le Premium |
/// | reste| panne réseau / API   | réessayer            |
///
/// Le `from` permet de revenir sur l'écran d'origine après l'inscription,
/// plutôt que de renvoyer l'utilisateur à l'accueil.
class ErreurChargement extends ConsumerWidget {
  /// L'erreur telle que la remonte Riverpod. Seul le statut HTTP compte ;
  /// tout ce qui n'est pas une `DioException` est traité comme une panne.
  final Object? erreur;

  /// Rappelé par le bouton « Réessayer ». Non proposé sur 401/403, où
  /// réessayer ne peut mener nulle part.
  final VoidCallback onRetry;

  /// Chemin de retour après connexion, ex. `/tutoriels`.
  final String? from;

  /// Complète le message générique : « le classement », « les tutoriels »…
  final String quoi;

  const ErreurChargement({
    super.key,
    required this.erreur,
    required this.onRetry,
    required this.quoi,
    this.from,
  });

  int? get _statut =>
      erreur is DioException ? (erreur as DioException).response?.statusCode : null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statut = _statut;

    final (icone, titre, detail, libelleAction, action) = switch (statut) {
      401 => (
        Icons.person_add_alt_1_rounded,
        'Crée ton compte',
        'Il faut un compte gratuit pour accéder à $quoi.',
        'Créer mon compte',
        () => context.push(from == null
            ? '/auth/email'
            : '/auth/email?from=${Uri.encodeComponent(from!)}'),
      ),
      403 => (
        Icons.workspace_premium_rounded,
        'Réservé aux membres Premium',
        'Passe au Premium pour débloquer $quoi.',
        'Découvrir le Premium',
        () => goToPremium(context, ref),
      ),
      _ => (
        Icons.wifi_off_rounded,
        'Connexion impossible',
        'Impossible de charger $quoi pour le moment.',
        'Réessayer',
        onRetry,
      ),
    };

    final couleur = switch (statut) {
      401 => AppColors.primary,
      403 => AppColors.warning,
      _   => AppColors.info,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 74, height: 74,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: couleur.withValues(alpha: 0.25), width: 0.8)),
            child: Icon(icone, color: couleur, size: 34)),
          const SizedBox(height: 18),
          Text(titre,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textS, fontSize: 13, height: 1.5)),
          const SizedBox(height: 22),
          Semantics(
            button: true,
            label: libelleAction,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: action,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: couleur,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(
                    color: couleur.withValues(alpha: 0.30),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    statut == 401 || statut == 403
                      ? Icons.arrow_forward_rounded
                      : Icons.refresh_rounded,
                    color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                  // Même défaut : le libellé d'action pousse la rangée dès que
                  // le texte est agrandi sur un petit écran.
                  Flexible(
                    child: Text(libelleAction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
