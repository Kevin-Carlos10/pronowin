import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/team_logo_widget.dart';
import '../../domain/entities/match_entity.dart';

/// Carte stylisée PronoWin destinée à être capturée en image puis partagée.
/// Dimensions logiques : 360 × 560 px → 1080 × 1680 px à pixelRatio 3.
class PronoShareCard extends StatelessWidget {
  final MatchEntity match;
  const PronoShareCard({super.key, required this.match});

  Color get _confColor {
    if (match.confidenceScore >= 5) return AppColors.success;
    if (match.confidenceScore >= 4) return const Color(0xFF84CC16);
    if (match.confidenceScore >= 3) return AppColors.warning;
    return AppColors.error;
  }

  String get _confLabel {
    if (match.confidenceScore >= 5) return 'Excellent';
    if (match.confidenceScore >= 4) return 'Fort';
    if (match.confidenceScore >= 3) return 'Bon';
    return 'Faible';
  }

  @override
  Widget build(BuildContext context) {
    final won = match.predictionWon;

    return SizedBox(
      width:  360,
      height: 560,
      child: Stack(children: [

        // ── Fond dégradé ───────────────────────────────────────────────────────
        Container(
          width: 360, height: 560,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0E1A), Color(0xFF111827), Color(0xFF0D1535)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        // ── Motif points décoratifs ────────────────────────────────────────────
        Positioned(
          top: -40, right: -40,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
          ),
        ),
        Positioned(
          bottom: 60, left: -60,
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.04),
            ),
          ),
        ),

        // ── Contenu ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              // ── Header : Logo + ligue ────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(text: 'Prono', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Win',   style: TextStyle(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      match.league,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Équipes ──────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Domicile
                  Expanded(
                    child: Column(children: [
                      TeamLogoWidget(url: match.homeTeamLogo, size: 64),
                      const SizedBox(height: 10),
                      Text(
                        match.homeTeam,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),

                  // Score ou VS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(children: [
                      if (match.status != MatchStatus.upcoming &&
                          match.homeScore != null && match.awayScore != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: match.status == MatchStatus.live
                                ? AppColors.error.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: match.status == MatchStatus.live
                                  ? AppColors.error.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            '${match.homeScore} - ${match.awayScore}',
                            style: TextStyle(
                              color: match.status == MatchStatus.live
                                  ? AppColors.error
                                  : Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        )
                      else ...[
                        Text('VS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('HH:mm', 'fr_FR').format(match.matchDate),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ]),
                  ),

                  // Extérieur
                  Expanded(
                    child: Column(children: [
                      TeamLogoWidget(url: match.awayTeamLogo, size: 64),
                      const SizedBox(height: 10),
                      Text(
                        match.awayTeam,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Badge résultat (si terminé) ──────────────────────────────────
              if (won != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: won
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: won
                          ? AppColors.success.withValues(alpha: 0.5)
                          : AppColors.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        won ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: won ? AppColors.success : AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        won ? 'Pronostic GAGNANT ✅' : 'Pronostic PERDU',
                        style: TextStyle(
                          color: won ? AppColors.success : AppColors.error,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Bloc pronostic ────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      AppColors.primary.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Column(children: [
                  const Text(
                    'PRONOSTIC',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    match.predictionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              // ── Cote + Confiance ──────────────────────────────────────────────
              Row(children: [
                // Cote
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.25)),
                    ),
                    child: Column(children: [
                      Text(
                        'COTE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        match.oddsRecommended.toStringAsFixed(2),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(width: 10),

                // Confiance
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _confColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _confColor.withValues(alpha: 0.25)),
                    ),
                    child: Column(children: [
                      Text(
                        'CONFIANCE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) => Container(
                          width: 10, height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i < match.confidenceScore
                                ? _confColor
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _confLabel,
                        style: TextStyle(
                          color: _confColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),

              const Spacer(),

              // ── Séparateur ────────────────────────────────────────────────────
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
                margin: const EdgeInsets.only(bottom: 14),
              ),

              // ── Date + CTA ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 11),
                    const SizedBox(width: 5),
                    Text(
                      DateFormat('dd MMM · HH:mm', 'fr_FR').format(match.matchDate),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ]),
                  Text(
                    'pronowin.app',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
