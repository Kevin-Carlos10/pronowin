package com.pronowin.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
class MainActivity : FlutterFragmentActivity() {

    /**
     * Le canal d'installation, et celui des réglages de notifications.
     *
     * Il est enregistré dans les deux variantes ; c'est [InstallateurApk] qui
     * refuse d'agir quand la permission n'est pas déclarée, c'est-à-dire sur le
     * paquet publié par les boutiques.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, InstallateurApk.CANAL)
            .setMethodCallHandler { appel, reponse ->
                when (appel.method) {
                    "peutInstaller" -> reponse.success(InstallateurApk.peutInstaller(this))
                    "espaceDisponible" -> reponse.success(InstallateurApk.espaceDisponible(this))
                    "installer" -> {
                        val chemin = appel.argument<String>("chemin")
                        if (chemin.isNullOrEmpty()) {
                            reponse.error("chemin_manquant", "Aucun chemin fourni", null)
                        } else {
                            InstallateurApk.installer(this, chemin, reponse)
                        }
                    }
                    else -> reponse.notImplemented()
                }
            }

        // Les réglages de notifications de l'application, quand elles sont
        // coupées au niveau du téléphone (reglages_systeme.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pronowin.app/reglages")
            .setMethodCallHandler { appel, reponse ->
                when (appel.method) {
                    "ouvrirNotifications" -> {
                        val intention = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.parse("package:$packageName"))
                        }
                        try {
                            startActivity(intention.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            reponse.success(null)
                        } catch (e: Exception) {
                            reponse.error("reglages_indisponibles", e.message, null)
                        }
                    }
                    else -> reponse.notImplemented()
                }
            }
    }
}
