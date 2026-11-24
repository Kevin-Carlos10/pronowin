import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pronowin/l10n/app_strings.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

/// Ce que l'abonnement donne, en chiffres réels (24 novembre 2026).
///
/// Le taux de réussite est réservé aux abonnés depuis le 23 novembre : le mur
/// Premium, qui s'adresse aux autres, n'avait plus d'argument chiffré. Ceux-ci
/// sont des comptes, pas un taux — les pronostics VIP publiés sur trente
/// jours, les compétitions couvertes, les pronostics VIP du jour. Le serveur
/// les calcule et tait ceux qui sont trop petits pour être annoncés
/// (`backend/src/services/chiffres_vip.ts`) ; l'écran n'affiche que ce qu'il
/// reçoit, sans rien recalculer.
class ChiffresVip {
  final int periodeJours;
  final int? vipPublies;
  final int? competitions;
  final int? vipAujourdhui;

  const ChiffresVip({
    required this.periodeJours,
    this.vipPublies,
    this.competitions,
    this.vipAujourdhui,
  });

  factory ChiffresVip.depuisApi(Map<String, dynamic> j) => ChiffresVip(
        periodeJours:  (j['periode_jours'] as num?)?.toInt() ?? 30,
        vipPublies:    (j['vip_publies'] as num?)?.toInt(),
        competitions:  (j['competitions'] as num?)?.toInt(),
        vipAujourdhui: (j['vip_aujourdhui'] as num?)?.toInt(),
      );

  bool get vide => vipPublies == null && competitions == null && vipAujourdhui == null;
}

/// Public côté serveur : le mur s'ouvre aussi pour un invité. Une erreur ne
/// l'empêche jamais de s'afficher — il se tait, simplement.
final chiffresVipProvider = FutureProvider.autoDispose<ChiffresVip?>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/pronostics/chiffres-vip');
    return ChiffresVip.depuisApi(Map<String, dynamic>.from(r.data as Map));
  } catch (_) {
    return null;
  }
});

/// Jusqu'à trois chiffres côte à côte ; rien du tout s'il n'y en a aucun.
///
/// [surFondSombre] : sur l'en-tête bleu nuit de la page d'offre, texte clair
/// et chiffres dorés.
class BandeauChiffresVip extends ConsumerWidget {
  final bool surFondSombre;
  const BandeauChiffresVip({super.key, this.surFondSombre = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(chiffresVipProvider).valueOrNull;
    if (c == null || c.vide) return const SizedBox.shrink();
    final compte = AppStrings.of(context);

    final tuiles = <(int, String)>[
      if (c.vipPublies != null)
        (c.vipPublies!, tr(context, "pronostics VIP publiés en {arg0} jours", [c.periodeJours])),
      if (c.competitions != null)
        (c.competitions!, tr(context, "compétitions couvertes")),
      if (c.vipAujourdhui != null)
        (c.vipAujourdhui!, compte.count(c.vipAujourdhui!,
            one: "pronostic VIP aujourd'hui", other: "pronostics VIP aujourd'hui")),
    ];

    final chiffre = surFondSombre ? const Color(0xFFFFD99A) : context.cl.textP;
    final legende = surFondSombre ? Colors.white70 : context.cl.textS;
    final fond = surFondSombre ? Colors.white.withValues(alpha: 0.06) : context.cl.surface;
    final bord = surFondSombre ? Colors.white.withValues(alpha: 0.10) : context.cl.border;

    return Container(
      key: const Key('chiffres-vip'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bord, width: 0.8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, (nombre, texte)) in tuiles.indexed) ...[
          if (i > 0) Container(width: 0.8, height: 40, color: bord),
          Expanded(
            child: Semantics(
              label: '$nombre $texte',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(children: [
                  Text('$nombre', style: TextStyle(
                    color: chiffre, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Text(texte, textAlign: TextAlign.center, style: TextStyle(
                    color: legende, fontSize: 11, height: 1.3)),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
