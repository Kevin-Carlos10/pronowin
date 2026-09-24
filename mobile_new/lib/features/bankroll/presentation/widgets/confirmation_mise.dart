import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/devise.dart';
import '../../../../shared/utils/montant.dart';
import '../providers/bankroll_provider.dart';

/// « Tu as bien misé 5 000 FCFA ? », posé au résultat d'un pari (constat M1
/// de l'audit du 24 septembre 2026).
///
/// La mise enregistrée était toujours la mise conseillée : le pari réellement
/// placé chez le bookmaker restait invisible, et le solde pouvait être faux
/// sans que rien ne le montre. La mise reste calculée et verrouillée à la
/// pose ; on demande seulement, une fois, si c'est bien elle. « Oui » en un
/// geste ; « corriger » pour les autres cas.
class ConfirmationMise extends ConsumerStatefulWidget {
  final BankrollBet bet;
  const ConfirmationMise({super.key, required this.bet});

  @override
  ConsumerState<ConfirmationMise> createState() => _ConfirmationMiseState();
}

class _ConfirmationMiseState extends ConsumerState<ConfirmationMise> {
  final _saisie = TextEditingController();
  bool _corriger = false;
  bool _envoi = false;
  String? _erreur;
  /// La réponse du serveur, une fois enregistrée : la carte la montre au lieu
  /// de reposer la question.
  ({double mise, bool corrigee})? _reponse;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _envoyer({double? miseReelle}) async {
    setState(() { _envoi = true; _erreur = null; });
    try {
      final r = await ref.read(dioProvider).post(
        '/bankroll/bet/${widget.bet.id}/confirmer',
        data: {'mise_reelle': ?miseReelle},
      );
      final corps = (r.data as Map).cast<String, dynamic>();
      HapticFeedback.mediumImpact();
      ref.invalidate(bankrollProvider);
      ref.invalidate(bankrollStatsProvider);
      if (mounted) {
        setState(() {
          _envoi = false;
          _reponse = (mise: (corps['mise'] as num).toDouble(), corrigee: corps['corrigee'] == true);
        });
      }
    } catch (e) {
      final message = e is DioException ? (e.response?.data?['message'] as String?) : null;
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreur = message ?? 'Réponse non enregistrée. Vérifie ta connexion et réessaie.';
        });
      }
    }
  }

  void _enregistrerCorrection() {
    final n = double.tryParse(_saisie.text.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));
    if (n == null || n < 0) {
      setState(() => _erreur = 'Indique le montant misé, ou « Je n\'ai pas misé ».');
      return;
    }
    _envoyer(miseReelle: n);
  }

  @override
  Widget build(BuildContext context) {
    final cl = context.cl;
    final devise = nomDevise(widget.bet.currency);
    final mise = '${montantExact(widget.bet.stakedAmount)} $devise';

    if (_reponse != null) {
      final r = _reponse!;
      return _Cadre(
        couleur: AppColors.success,
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(
            r.corrigee
                ? (r.mise == 0
                    ? 'Noté : pas de mise sur ce pari. Ta bankroll est à jour.'
                    : 'Mise corrigée : ${montantExact(r.mise)} $devise. Ta bankroll est à jour.')
                : 'Mise confirmée. Merci !',
            style: TextStyle(color: cl.textP, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      );
    }

    return _Cadre(
      couleur: AppColors.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Tu as bien misé $mise ?',
          style: TextStyle(color: cl.textP, fontSize: 15.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Chez ton bookmaker, sur ce pari. Ta bankroll suit ta mise réelle.',
          style: TextStyle(color: cl.textM, fontSize: 12.5)),
        const SizedBox(height: 14),

        if (!_corriger) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: ElevatedButton(
              onPressed: _envoi ? null : () => _envoyer(),
              child: _envoi
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Oui, c\'est ça', textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _envoi ? null : () => setState(() { _corriger = true; _erreur = null; }),
            child: const Text('Non, corriger'),
          ),
        ] else ...[
          TextField(
            controller: _saisie,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Montant réellement misé',
              suffixText: devise,
              hintText: montantExact(widget.bet.stakedAmount),
            ),
            onSubmitted: (_) => _enregistrerCorrection(),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton(
              onPressed: _envoi ? null : _enregistrerCorrection,
              child: const Text('Enregistrer'),
            ),
            OutlinedButton(
              onPressed: _envoi ? null : () => _envoyer(miseReelle: 0),
              child: const Text('Je n\'ai pas misé'),
            ),
            TextButton(
              onPressed: _envoi ? null : () => setState(() { _corriger = false; _erreur = null; }),
              child: const Text('Annuler'),
            ),
          ]),
        ],

        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
        ],
      ]),
    );
  }
}

class _Cadre extends StatelessWidget {
  final Color couleur;
  final Widget child;
  const _Cadre({required this.couleur, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cl.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: couleur.withValues(alpha: 0.4), width: 1),
    ),
    child: child,
  );
}
