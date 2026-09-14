package com.pronowin.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Remet un APK téléchargé à l'installateur du système.
 *
 * L'APK distribué depuis le site ne se met pas à jour tout seul. Jusqu'ici la
 * seule voie était d'ouvrir l'adresse dans le navigateur : l'utilisateur
 * quittait l'application, cherchait le fichier dans ses téléchargements, et
 * revenait — ou ne revenait pas. L'application télécharge désormais elle-même,
 * affiche l'avancement, puis passe le fichier ici.
 *
 * ── Ce code existe dans les deux variantes, la permission non ───────────────
 *
 * Il vit dans `src/main` parce que `MainActivity` y vit aussi, et qu'une
 * variante ne peut pas ajouter de code à une activité définie ailleurs. Ce
 * n'est pas un problème : sans REQUEST_INSTALL_PACKAGES — que seule la
 * variante « direct » déclare — ce code refuse de faire quoi que ce soit, et
 * le dit. Un paquet Play qui l'atteindrait par erreur échouerait bruyamment
 * plutôt que d'ouvrir un réglage système que l'utilisateur ne pourrait pas
 * satisfaire.
 */
object InstallateurApk {

    /** Nom du canal, à tenir identique côté Dart. */
    const val CANAL = "com.pronowin.app/installateur"

    private const val PERMISSION = "android.permission.REQUEST_INSTALL_PACKAGES"

    /** La variante courante déclare-t-elle la permission d'installer ? */
    private fun permissionDeclaree(activite: Activity): Boolean = try {
        activite.packageManager
            .getPackageInfo(activite.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.contains(PERMISSION) == true
    } catch (e: Exception) {
        false
    }

    /**
     * L'utilisateur a-t-il autorisé cette application à installer des paquets ?
     *
     * Depuis Android 8, l'autorisation est accordée application par
     * application, et pas globalement comme le réglage « sources inconnues »
     * d'autrefois. Déclarer la permission ne suffit donc pas.
     */
    fun peutInstaller(activite: Activity): Boolean {
        if (!permissionDeclaree(activite)) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return activite.packageManager.canRequestPackageInstalls()
    }

    /**
     * Ouvre l'installateur sur [chemin].
     *
     * Rend `true` si l'installateur s'est ouvert, `false` si l'utilisateur a
     * d'abord été envoyé vers le réglage d'autorisation — auquel cas il faudra
     * réessayer au retour. Une erreur signifie que l'installation est
     * impossible sur ce paquet.
     */
    fun installer(activite: Activity, chemin: String, reponse: MethodChannel.Result) {
        if (!permissionDeclaree(activite)) {
            reponse.error(
                "canal_store",
                "Ce paquet ne declare pas $PERMISSION : il vient d'une boutique " +
                    "et se met a jour par elle.",
                null,
            )
            return
        }

        val fichier = File(chemin)
        if (!fichier.exists() || fichier.length() == 0L) {
            reponse.error("fichier_absent", "Aucun fichier exploitable a $chemin", null)
            return
        }

        // L'autorisation se demande au moment de s'en servir, pas au démarrage :
        // un réglage système réclamé sans raison visible n'est pas accordé.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activite.packageManager.canRequestPackageInstalls()
        ) {
            try {
                activite.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activite.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                reponse.success(false)
            } catch (e: Exception) {
                reponse.error("reglage_introuvable", e.message, null)
            }
            return
        }

        try {
            val uri: Uri = FileProvider.getUriForFile(
                activite,
                "${activite.packageName}.installateur",
                fichier,
            )
            activite.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            reponse.success(true)
        } catch (e: Exception) {
            reponse.error("installation_impossible", e.message, null)
        }
    }
}
