import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_provider.dart';

// ─── État du verrou ───────────────────────────────────────────────────────────
class SecurityState {
  final bool isLocked;           // App est-elle verrouillée ?
  final bool bioAvailable;       // Biométrie disponible sur cet appareil ?
  final List<BiometricType> biometrics; // Types de biométrie dispos

  const SecurityState({
    this.isLocked       = false,
    this.bioAvailable   = false,
    this.biometrics     = const [],
  });
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class SecurityNotifier extends StateNotifier<SecurityState> {
  SecurityNotifier() : super(const SecurityState()) {
    _checkBioAvailability();
  }

  final _auth = LocalAuthentication();

  /// Vérifie si la biométrie est disponible sur l'appareil
  Future<void> _checkBioAvailability() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      final biometrics = canCheck ? await _auth.getAvailableBiometrics() : <BiometricType>[];
      state = SecurityState(
        bioAvailable: canCheck && isSupported,
        biometrics:   biometrics,
      );
      debugPrint('[Security] Bio disponible: $bioAvailable | Types: $biometrics');
    } catch (e) {
      debugPrint('[Security] Erreur bio: $e');
    }
  }

  bool get bioAvailable => state.bioAvailable;

  /// Authentifier par biométrie
  Future<bool> authenticateWithBio() async {
    if (!state.bioAvailable) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Déverrouillez PronoWin',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth:    true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('[Security] Erreur auth bio: $e');
      return false;
    }
  }

  /// Valider un PIN
  Future<bool> validatePin(String pin) async {
    final p     = await SharedPreferences.getInstance();
    final saved = p.getString('pin_code') ?? '';
    return pin == saved && saved.isNotEmpty;
  }

  /// Vérifier si l'app doit être verrouillée au démarrage
  Future<bool> shouldLock(WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    if (!settings.pinEnabled && !settings.bioEnabled) return false;
    final p = await SharedPreferences.getInstance();
    final hasPin = p.getString('pin_code')?.isNotEmpty ?? false;
    return hasPin || settings.bioEnabled;
  }
}

final securityProvider = StateNotifierProvider<SecurityNotifier, SecurityState>(
  (_) => SecurityNotifier());

// ─── Provider accessibilité biométrie ─────────────────────────────────────────
final bioAvailableProvider = FutureProvider<bool>((ref) async {
  final auth = LocalAuthentication();
  try {
    final can = await auth.canCheckBiometrics;
    final sup = await auth.isDeviceSupported();
    return can && sup;
  } catch (_) { return false; }
});
