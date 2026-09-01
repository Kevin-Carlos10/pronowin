import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/pin_store.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class LockScreenPage extends ConsumerStatefulWidget {
  final String redirectTo;
  const LockScreenPage({super.key, this.redirectTo = '/home'});

  @override
  ConsumerState<LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends ConsumerState<LockScreenPage> {
  final _auth    = LocalAuthentication();
  String _pin    = '';
  String _error  = '';
  int    _attempts = 0;
  static const _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBio());
  }

  Future<void> _tryBio() async {
    final settings = ref.read(settingsProvider);
    if (!settings.bioEnabled) return;

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isAvailable = await _auth.isDeviceSupported();
      if (!canCheck || !isAvailable) return;

      final authenticated = await _auth.authenticate(
        localizedReason: 'Déverrouillez PronoWin avec ton empreinte',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth:    true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated && mounted) _unlock();
    } catch (e) {
      debugPrint('[Bio] Erreur: $e');
    }
  }

  void _onKey(String digit) {
    if (_pin.length >= 4 || _attempts >= _maxAttempts) return;
    setState(() {
      _error = '';
      _pin  += digit;
    });
    if (_pin.length == 4) _validatePin();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _validatePin() async {
    if (await ref.read(pinStoreProvider).verify(_pin)) {
      if (mounted) _unlock();
    } else {
      setState(() {
        _attempts++;
        _error = _attempts >= _maxAttempts
          ? 'Trop de tentatives. Reconnecte-toi.'
          : 'Code incorrect. ${_maxAttempts - _attempts} essai(s) restant(s).';
        _pin = '';
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _unlock() => context.go(widget.redirectTo);

  @override
  Widget build(BuildContext context) {
    final settings    = ref.watch(settingsProvider);
    final bioEnabled  = settings.bioEnabled;
    final blocked     = _attempts >= _maxAttempts;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.cl.bg,
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 60),

            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),

            RichText(text: TextSpan(
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              children: [
                TextSpan(text: 'Prono', style: TextStyle(color: context.cl.textP)),
                const TextSpan(text: 'Win',   style: TextStyle(color: AppColors.primary)),
              ],
            )),
            SizedBox(height: 8),
            Text('Entrez ton code PIN', style: TextStyle(
              color: context.cl.textS, fontSize: 14)),
            const SizedBox(height: 40),

            // Points PIN
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
              final filled = i < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: filled ? 18 : 14,
                height: filled ? 18 : 14,
                decoration: BoxDecoration(
                  color: _error.isNotEmpty ? AppColors.error
                    : (filled ? AppColors.primary : Colors.transparent),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _error.isNotEmpty ? AppColors.error
                      : (filled ? AppColors.primary : context.cl.borderS),
                    width: 2),
                ),
              );
            })),
            const SizedBox(height: 16),

            AnimatedOpacity(
              opacity: _error.isEmpty ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Text(
                _error,
                style: TextStyle(
                  color: blocked ? AppColors.error : AppColors.warning,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: blocked
                  ? _buildBlockedView()
                  : _buildKeypad(bioEnabled),
              ),
            ),

            // Sortie de secours : sans elle, oublier son code enfermait
            // définitivement l'utilisateur hors de l'app — bankroll comprise.
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton(
                onPressed: _codeOublie,
                child: Text('Code oublié ?',
                    style: TextStyle(
                        color: context.cl.textM,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Déverrouillage impossible : la seule issue sûre est de fermer la session.
  /// On ne propose surtout pas de « réinitialiser le code » sur place, ce qui
  /// annulerait la protection pour quiconque tient l'appareil en main.
  Future<void> _codeOublie() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: dctx.cl.surface,
        title: const Text('Code oublié'),
        content: const Text(
            'Pour retrouver l\'accès, il faut te déconnecter puis te '
            'reconnecter avec ton compte. Tes données ne sont pas perdues.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    // Le code est effacé avec la session : le prochain démarrage repart d'un
    // écran de connexion normal, sans verrou orphelin.
    await ref.read(pinStoreProvider).clear();
    await ref.read(settingsProvider.notifier).setPinEnabled(false);
    await ref.read(authProvider.notifier).logout();
    // `/auth` n'est pas une route : seuls `/auth/email` et `/auth/email/otp`
    // existent. Se déconnecter depuis le verrou menait donc à la page d'erreur
    // du routeur — au moment précis où l'utilisateur n'a plus que ce chemin,
    // puisqu'il vient d'oublier son code.
    if (mounted) context.go('/auth/email');
  }

  Widget _buildKeypad(bool bioEnabled) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      ...[['1','2','3'],['4','5','6'],['7','8','9']].map((row) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((d) => _KeyButton(digit: d, onTap: () => _onKey(d))).toList(),
          ),
        )),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        SizedBox(width: 80, child: bioEnabled
          ? IconButton(
              onPressed: _tryBio,
              icon: const Icon(Icons.fingerprint_rounded,
                color: AppColors.primary, size: 32))
          : const SizedBox()),
        _KeyButton(digit: '0', onTap: () => _onKey('0')),
        SizedBox(width: 80, child: IconButton(
          onPressed: _onDelete,
          icon: Icon(Icons.backspace_outlined,
            color: context.cl.textS, size: 24))),
      ]),
    ],
  );

  Widget _buildBlockedView() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.lock_outlined, color: AppColors.error, size: 56),
      const SizedBox(height: 16),
      Text('Compte verrouillé', style: TextStyle(
        color: AppColors.error, fontSize: 18, fontWeight: FontWeight.w700)),
      SizedBox(height: 8),
      Text('Trop de tentatives incorrectes.\nReconnecte-toi pour continuer.',
        style: TextStyle(color: context.cl.textS, fontSize: 13),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: () => context.go('/auth/email'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
        child: const Text('Se reconnecter'),
      ),
    ],
  );
}

class _KeyButton extends StatelessWidget {
  final String digit; final VoidCallback onTap;
  const _KeyButton({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        color: context.cl.surface, shape: BoxShape.circle,
        border: Border.all(color: context.cl.border, width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Center(child: Text(digit, style: TextStyle(
        color: context.cl.textP, fontSize: 26, fontWeight: FontWeight.w500))),
    ),
  );
}
