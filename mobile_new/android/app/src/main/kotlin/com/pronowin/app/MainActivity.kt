package com.pronowin.app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * L'activité hôte doit être une [androidx.fragment.app.FragmentActivity].
 *
 * Le plugin `local_auth` affiche le `BiometricPrompt` d'AndroidX dans un
 * fragment. Il refuse donc toute autre activité, et pas discrètement :
 *
 *     // LocalAuthPlugin.java
 *     if (!(activity instanceof FragmentActivity)) {
 *       result.success(AuthResult.ERROR_NOT_FRAGMENT_ACTIVITY);
 *       return;
 *     }
 *
 * ce qui remonte côté Dart en `PlatformException(no_fragment_activity)`.
 *
 * Avec le `FlutterActivity` d'origine, l'empreinte digitale ne pouvait donc
 * jamais fonctionner sur Android — et le défaut était invisible, parce que
 * `canCheckBiometrics` et `isDeviceSupported` interrogent `BiometricManager`
 * sans passer par l'activité : l'écran annonçait la biométrie comme
 * disponible, puis échouait au moment de s'en servir.
 *
 * `FlutterFragmentActivity` hérite de `FragmentActivity` et se comporte
 * autrement comme `FlutterActivity`. Le thème `Theme.Black.NoTitleBar` reste
 * valable : `androidx.biometric:1.1.0` n'exige plus de thème AppCompat.
 */
class MainActivity : FlutterFragmentActivity()
