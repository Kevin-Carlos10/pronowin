import 'package:flutter/material.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Bouton principal PronoWin avec gradient, animation scale et haptic feedback.
///
/// ── Ce qui a changé ────────────────────────────────────────────────────────
///
///   · Le dégradé allait de l'orange au jaune (#F5A623) : le libellé blanc
///     tombait à 2,03:1 côté jaune. Il passe par [AppColors.degradeBouton],
///     lisible sur toute sa largeur (≥ 5:1).
///   · Ce n'était qu'un `GestureDetector` : VoiceOver et TalkBack n'y
///     voyaient pas de bouton, ni son état désactivé ou occupé. Le
///     `Semantics` les annonce.
///   · Sa hauteur était fixée à 52 : elle est maintenant un minimum, et le
///     bouton grandit avec le texte agrandi au lieu de le rogner.
class PwButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  final IconData? icon;
  final Color? color;

  const PwButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.outlined = false,
    this.icon,
    this.color,
  });

  @override
  State<PwButton> createState() => _PwButtonState();
}

class _PwButtonState extends State<PwButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      HapticFeedback.lightImpact();
      _ctrl.forward();
    }
  }

  void _onTapUp(TapUpDetails _) => _ctrl.reverse();
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;

    // Un seul nœud pour le lecteur d'écran : « Continuer, bouton », grisé
    // quand il est désactivé, « occupé » pendant le chargement.
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      value: widget.isLoading ? tr(context, "Traitement en cours") : null,
      excludeSemantics: true,
      child: ScaleTransition(
        scale: _scale,
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onTap: disabled ? null : widget.onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52, minWidth: double.infinity),
            child: widget.outlined ? _contour(context, disabled) : _plein(context, disabled),
          ),
        ),
      ),
    );
  }

  Widget _contour(BuildContext context, bool disabled) {
    final couleur = widget.color ?? context.cl.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: disabled ? context.cl.borderS : couleur.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: Center(child: _buildContent(couleur, outlined: true)),
    );
  }

  Widget _plein(BuildContext context, bool disabled) {
    // Une couleur imposée reste unie : on ne sait pas quelle teinte lui
    // associer sans retomber sur un bout de dégradé illisible.
    final couleurs = disabled
        ? [context.cl.borderS, context.cl.borderS]
        : widget.color != null
            ? [widget.color!, widget.color!]
            : AppColors.degradeBouton;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: couleurs,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: disabled
            ? const []
            : [
                BoxShadow(
                  color: couleurs.first.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      // Désactivé, le fond est gris clair : un libellé blanc y disparaissait.
      child: Center(child: _buildContent(disabled ? context.cl.textM : Colors.white, outlined: false)),
    );
  }

  Widget _buildContent(Color color, {required bool outlined}) {
    if (widget.isLoading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: outlined ? context.cl.accent : Colors.white,
        ),
      );
    }
    // Le libellé n'avait aucune contrainte : ni `Flexible`, ni troncature.
    // « Créer un compte gratuit pour continuer » débordait le bouton de 196 px
    // sur un écran de 411, et de 287 px sur un 320 — sans même agrandir le
    // texte. Le bouton occupe toute la largeur, ce qui donnait l'illusion qu'il
    // y avait la place ; son contenu n'en savait rien.
    //
    // Deux lignes plutôt qu'une ellipse : un libellé d'action coupé ne dit
    // plus ce que fait le bouton. La hauteur suit.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: color),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
