import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../data/pin_store.dart';
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
}

/// Traduit un échec d'authentification biométrique en phrase lisible.
///
/// Le toggle affichait `Erreur biométrie : PlatformException(no_fragment_activity,
/// local_auth plugin requires activity to be a FragmentActivity., null, null)`.
/// Cette chaîne ne dit rien à qui la lit, et masquait justement le défaut de
/// configuration Android qui empêchait la biométrie de fonctionner.
String messageErreurBio(Object e) {
  final code = e is PlatformException ? e.code : '';
  switch (code) {
    case 'NotAvailable':
      return 'La biométrie n\'est pas disponible sur cet appareil.';
    case 'NotEnrolled':
      return 'Aucune empreinte ni visage enregistré. Ajoute-les dans les '
             'réglages de ton téléphone, puis reviens ici.';
    case 'PasscodeNotSet':
      return 'Ton téléphone n\'a pas de verrouillage d\'écran. Configure-le '
             'd\'abord dans les réglages du système.';
    case 'LockedOut':
      return 'Trop de tentatives. Réessaie dans quelques instants.';
    case 'PermanentlyLockedOut':
      return 'Biométrie bloquée. Déverrouille ton téléphone avec son code, '
             'puis réessaie.';
    case 'no_fragment_activity':
      // Ne devrait plus se produire depuis que MainActivity hérite de
      // FlutterFragmentActivity. Si le message réapparaît, la classe hôte a
      // été modifiée — le texte le dit franchement plutôt que de laisser
      // croire à une limite de l'appareil.
      return 'Configuration de l\'application incorrecte : la biométrie ne '
             'peut pas démarrer. Signale-le au support.';
    default:
      return 'La biométrie n\'a pas pu démarrer. Réessaie, ou utilise ton '
             'code PIN.';
  }
}

/// L'app doit-elle présenter l'écran de verrouillage ?
///
/// Cette décision était écrite trois fois : ici, et deux fois dans `main.dart`
/// (au démarrage et au retour d'arrière-plan), chaque copie relisant elle-même
/// `SharedPreferences`. La version de ce fichier n'était appelée nulle part —
/// elle a donc conservé l'ancienne lecture en clair pendant que les autres
/// évoluaient. Une seule fonction, appelée partout, supprime la dérive.
///
/// Les dépendances sont passées explicitement plutôt que via un `Ref` : les
/// appelants tiennent tantôt un `Ref`, tantôt un `WidgetRef` — deux types sans
/// parenté — et cette forme se teste sans monter de conteneur.
Future<bool> doitVerrouiller({
  required AppSettings settings,
  required PinStore pinStore,
}) async {
  if (!settings.pinEnabled && !settings.bioEnabled) return false;
  // Le verrou biométrique se suffit à lui-même ; sinon il faut un code défini,
  // sans quoi l'écran de verrouillage s'afficherait sans moyen d'en sortir.
  if (settings.bioEnabled) return true;
  return pinStore.hasPin();
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
