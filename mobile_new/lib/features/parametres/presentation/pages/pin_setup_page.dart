import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';

class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key});
  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  String _pin     = '';
  String _confirm = '';
  bool   _step2   = false; // false = saisir, true = confirmer
  String _error   = '';

  void _onKey(String digit) {
    HapticFeedback.selectionClick();
    setState(() {
      _error = '';
      if (!_step2) {
        if (_pin.length < 4) {
          _pin += digit;
          if (_pin.length == 4) _step2 = true;
        }
      } else {
        if (_confirm.length < 4) {
          _confirm += digit;
          if (_confirm.length == 4) _validate();
        }
      }
    });
  }

  void _onDelete() {
    HapticFeedback.lightImpact();
    setState(() {
      _error = '';
      if (_step2) {
        if (_confirm.isNotEmpty) _confirm = _confirm.substring(0, _confirm.length - 1);
      } else {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _validate() async {
    if (_pin == _confirm) {
      HapticFeedback.mediumImpact();
      final p = await SharedPreferences.getInstance();
      await p.setString('pin_code', _pin);
      await ref.read(settingsProvider.notifier).setPinEnabled(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Code PIN activé avec succès ✅'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        context.pop();
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error   = 'Les codes ne correspondent pas. Recommencez.';
        _pin     = '';
        _confirm = '';
        _step2   = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _step2 ? _confirm : _pin;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(_step2 ? 'Confirmer le PIN' : 'Créer un code PIN'),
      ),
      body: Column(children: [
        const SizedBox(height: 40),

        // Titre
        Text(
          _step2 ? 'Confirmez ton code PIN' : 'Choisis un code PIN à 4 chiffres',
          style: TextStyle(color: context.cl.textP, fontSize: 18, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        Text(
          _step2 ? 'Entrez à nouveau le même code' : 'Ce code protégera l\'accès à l\'application',
          style: TextStyle(color: context.cl.textS, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Points PIN
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
          final filled = i < current.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: filled ? 20 : 16,
            height: filled ? 20 : 16,
            decoration: BoxDecoration(
              color: filled ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled ? AppColors.primary : context.cl.borderS,
                width: 2),
            ),
          );
        })),
        const SizedBox(height: 12),

        // Erreur
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 13),
              textAlign: TextAlign.center),
          ),
        const SizedBox(height: 32),

        // Clavier
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...[['1','2','3'],['4','5','6'],['7','8','9']].map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: row.map((d) => _PinButton(digit: d, onTap: () => _onKey(d))).toList(),
                  ),
                )),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  SizedBox(width: 80),
                  _PinButton(digit: '0', onTap: () => _onKey('0')),
                  SizedBox(width: 80, child: IconButton(
                    onPressed: _onDelete,
                    icon: Icon(Icons.backspace_outlined, color: context.cl.textS, size: 24),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _PinButton extends StatelessWidget {
  final String digit; final VoidCallback onTap;
  const _PinButton({required this.digit, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        color: context.cl.surface, shape: BoxShape.circle,
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Center(child: Text(digit, style: TextStyle(
        color: context.cl.textP, fontSize: 26, fontWeight: FontWeight.w500))),
    ),
  );
}
