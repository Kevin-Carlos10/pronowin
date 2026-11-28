import 'dart:async';

import 'package:flutter/widgets.dart';

/// Le temps qui reste avant le coup d'envoi, à la seconde : « 03:19:13 ».
///
/// Repris de 1xBet (vidéo du 8 novembre 2026, « Démarre dans 03:19:13 » sur
/// la fiche d'un match à venir). La fiche de PronoWin ne donnait que l'heure
/// et la date ; l'accueil avait déjà ce décompte pour le « Top du jour ».
String texteDecompte(Duration reste) {
  final s = reste.inSeconds < 0 ? 0 : reste.inSeconds;
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(s ~/ 3600)}:${deux(s % 3600 ~/ 60)}:${deux(s % 60)}';
}

/// Reconstruit [builder] chaque seconde avec le temps restant, tant que le
/// coup d'envoi est à moins de [horizon]. Au-delà, ou une fois passé
/// d'une heure, [builder] reçoit null et la minuterie s'arrête.
class DecompteCoupEnvoi extends StatefulWidget {
  const DecompteCoupEnvoi({
    super.key,
    required this.coupEnvoi,
    required this.builder,
    this.horizon = const Duration(hours: 24),
  });

  final DateTime coupEnvoi;
  final Duration horizon;
  final Widget Function(BuildContext context, Duration? reste) builder;

  /// L'heure courante : remplaçable pour les tests.
  @visibleForTesting
  static DateTime Function() horloge = DateTime.now;

  @override
  State<DecompteCoupEnvoi> createState() => _DecompteCoupEnvoiState();
}

class _DecompteCoupEnvoiState extends State<DecompteCoupEnvoi> {
  Timer? _minuterie;

  Duration? get _reste {
    final r = widget.coupEnvoi.difference(DecompteCoupEnvoi.horloge());
    if (r > widget.horizon) return null;
    // Un match « à venir » dont l'heure est passée : la source ne l'a pas
    // encore déclaré commencé. On le dit imminent une heure durant, puis on
    // revient à la date.
    if (r < const Duration(hours: -1)) return null;
    return r;
  }

  @override
  void initState() {
    super.initState();
    _armer();
  }

  @override
  void didUpdateWidget(DecompteCoupEnvoi ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.coupEnvoi != widget.coupEnvoi) _armer();
  }

  void _armer() {
    _minuterie?.cancel();
    final r = widget.coupEnvoi.difference(DecompteCoupEnvoi.horloge());
    if (r < const Duration(hours: -1)) return;
    if (r > widget.horizon) {
      // Trop loin : rien ne bouge à l'écran. On se réveille à l'horizon.
      _minuterie = Timer(r - widget.horizon, () {
        if (mounted) setState(_armer);
      });
      return;
    }
    _minuterie = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_reste == null) _minuterie?.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reste);
}
