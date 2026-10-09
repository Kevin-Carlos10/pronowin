import 'package:pronowin/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/pin_store.dart';
import '../providers/security_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../../../../shared/widgets/logotype_pronowin.dart';

class LockScreenPage extends ConsumerStatefulWidget {
  final String redirectTo;
  const LockScreenPage({super.key, this.redirectTo = '/home'});

  @override
  ConsumerState<LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends ConsumerState<LockScreenPage> {
  late final LocalAuthentication _auth;
  String _pin    = '';
  String _error  = '';
  int    _attempts = 0;
  bool _authenticating = false;
  bool _validating = false;
  bool _unlocked = false;
  static const _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(localAuthenticationProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBio());
  }

  Future<void> _tryBio() async {
    final settings = ref.read(settingsProvider);
    if (!settings.bioEnabled || _authenticating || _unlocked) return;
    setState(() { _authenticating = true; _error = ''; });

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isAvailable = await _auth.isDeviceSupported();
      if (!mounted) return;
      if (!canCheck || !isAvailable) {
        setState(() => _error = tr(context, "La biométrie n'est pas disponible sur cet appareil."));
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: trCurrent("Déverrouille PronoWin"),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth:    true,
          useErrorDialogs: true,
        ),
      );

      if (mounted) {
        if (authenticated) { _unlock(); }
        else { setState(() => _error = tr(context, "Authentification annulée. Réessaie pour déverrouiller.")); }
      }
    } catch (e) {
      if (mounted) setState(() => _error = tr(context, "Impossible de déverrouiller. Réessaie ou reconnecte-toi."));
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  void _onKey(String digit) {
    if (!ref.read(settingsProvider).pinEnabled || _validating || _unlocked || _pin.length >= 4 || _attempts >= _maxAttempts) return;
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
    if (_validating || !ref.read(settingsProvider).pinEnabled) return;
    _validating = true;
    final correct = await ref.read(pinStoreProvider).verify(_pin);
    _validating = false;
    if (!mounted) return;
    if (correct) {
      if (mounted) _unlock();
    } else {
      setState(() {
        _attempts++;
        _error = _attempts >= _maxAttempts
          ? tr(context, "Trop de tentatives. Reconnecte-toi.")
          : tr(context, "Code incorrect. {arg0} essai(s) restant(s).", [_maxAttempts - _attempts]);
        _pin = '';
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _unlock() {
    if (_unlocked) return;
    _unlocked = true;
    context.go(widget.redirectTo);
  }

  @override
  void dispose() {
    _auth.stopAuthentication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings    = ref.watch(settingsProvider);
    final bioEnabled  = settings.bioEnabled;
    final pinEnabled = settings.pinEnabled;
    final face = ref.watch(securityProvider).biometrics.contains(BiometricType.face);
    final blocked     = _attempts >= _maxAttempts;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.cl.bg,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(child: Column(children: [
            const SizedBox(height: 60),

            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.degradeMarque,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),

            const LogotypePronoWin(taille: 24),
            SizedBox(height: 8),
            Text(pinEnabled ? tr(context, "Entre ton code PIN") : tr(context, "Déverrouille PronoWin"), style: TextStyle(
              color: context.cl.textS, fontSize: 14)),
            const SizedBox(height: 40),

            // Points PIN
            if (pinEnabled) Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
              final filled = i < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: filled ? 18 : 14,
                height: filled ? 18 : 14,
                decoration: BoxDecoration(
                  color: _error.isNotEmpty ? context.cl.error
                    : (filled ? AppColors.primary : Colors.transparent),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _error.isNotEmpty ? context.cl.error
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
                  color: blocked ? context.cl.error : context.cl.warning,
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
                  : pinEnabled ? _buildKeypad(bioEnabled) : Center(
                    child: FilledButton.icon(
                      onPressed: _authenticating ? null : _tryBio,
                      icon: Icon(face ? Icons.face_rounded : Icons.lock_open_rounded),
                      label: Text(_authenticating ? tr(context, "Vérification…") : face ? 'Face ID' : tr(context, "Déverrouiller")),
                    ),
                  ),
              ),
            ),

            // Sortie de secours : sans elle, oublier son code enfermait
            // définitivement l'utilisateur hors de l'app — bankroll comprise.
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton(
                onPressed: _codeOublie,
                child: Text(pinEnabled ? tr(context, "Code oublié ?") : tr(context, "Se reconnecter"),
                    style: TextStyle(
                        color: context.cl.textM,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ])),
            ),
          )),
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
        title: Text(tr(context, "Se reconnecter")),
        content:  Text(
            tr(context, "Pour retrouver l'accès, il faut te déconnecter puis te reconnecter avec ton compte. Tes données ne sont pas perdues.")),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child:  Text(tr(context, "Annuler"))),
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child:  Text(tr(context, "Se déconnecter"))),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    // Le code est effacé avec la session : le prochain démarrage repart d'un
    // écran de connexion normal, sans verrou orphelin.
    await _auth.stopAuthentication();
    if (!mounted) return;
    await ref.read(pinStoreProvider).clear();
    await ref.read(settingsProvider.notifier).setPinEnabled(false);
    await ref.read(settingsProvider.notifier).setBioEnabled(false);
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
              onPressed: _authenticating ? null : _tryBio,
              tooltip: tr(context, "Déverrouiller"),
              icon: Icon(ref.watch(securityProvider).biometrics.contains(BiometricType.face) ? Icons.face_rounded : Icons.fingerprint_rounded,
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
      Icon(Icons.lock_outlined, color: context.cl.error, size: 56),
      const SizedBox(height: 16),
      Text(tr(context, "Compte verrouillé"), style: TextStyle(
        color: context.cl.error, fontSize: 18, fontWeight: FontWeight.w700)),
      SizedBox(height: 8),
      Text(tr(context, "Trop de tentatives incorrectes.\nReconnecte-toi pour continuer."),
        style: TextStyle(color: context.cl.textS, fontSize: 13),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _codeOublie,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.fondErreur),
        child:  Text(tr(context, "Se reconnecter")),
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
