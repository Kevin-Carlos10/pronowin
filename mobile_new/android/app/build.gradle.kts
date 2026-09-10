import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Clé de signature de publication ─────────────────────────────────────────
//
// `android/key.properties` porte les secrets ; il est ignoré par git, comme le
// magasin de clés lui-même (`*.jks`). Voir `android/key.properties.example`.
//
// Sans ce fichier, la version release était signée avec la **clé de débogage** :
// un paquet que Google Play refuse, et que rien dans la sortie de build ne
// signalait. On croyait produire un artefact publiable ; il ne l'était pas.
val fichierCle = rootProject.file("key.properties")
val cle = Properties().apply {
    if (fichierCle.exists()) fichierCle.inputStream().use { load(it) }
}
val cleDisponible = fichierCle.exists() &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !cle.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.pronowin.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pronowin.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (cleDisponible) {
            create("release") {
                storeFile     = file(cle.getProperty("storeFile"))
                storePassword = cle.getProperty("storePassword")
                keyAlias      = cle.getProperty("keyAlias")
                keyPassword   = cle.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Repli de débogage, mais **jamais en silence** — voir le contrôle
            // posé plus bas, hors du bloc `android`.
            signingConfig = signingConfigs.getByName(
                if (cleDisponible) "release" else "debug")
        }
    }
}

/**
 * Interdit de produire une version *release* signée avec la clé de débogage.
 *
 * Un tel paquet s'installe, se lance et se teste normalement : rien ne le
 * distingue à l'usage. Il ne se révèle qu'au téléversement sur Play — ou pire,
 * par une connexion Google qui échoue en production, l'empreinte enregistrée
 * n'étant pas celle du paquet.
 *
 * ⚠️ Le contrôle vit **ici**, et pas dans `buildTypes.release { }`.
 *
 * Gradle évalue l'intégralité du script à la configuration, quelle que soit la
 * tâche demandée : un `throw` placé dans le bloc `release` se déclenchait aussi
 * pour `assembleDebug`, et cassait `flutter run`. Le graphe des tâches, lui,
 * dit ce qui va réellement être construit.
 */
if (!cleDisponible) {
    gradle.taskGraph.whenReady {
        val produitUnRelease = allTasks.any { t ->
            t.name.contains("Release") &&
            listOf("assemble", "bundle", "package").any { t.name.startsWith(it) }
        }
        if (!produitUnRelease) return@whenReady

        if (project.findProperty("signatureDebogage") != "true") {
            throw GradleException(
                "Aucune cle de publication : android/key.properties est absent ou incomplet.\n" +
                "  * Pour publier : creez la cle (voir android/key.properties.example).\n" +
                "  * Pour un essai local : relancez avec -PsignatureDebogage=true\n" +
                "    (le paquet produit sera REFUSE par Google Play)."
            )
        }
        logger.warn(
            "\n  ATTENTION : version release signee avec la CLE DE DEBOGAGE.\n" +
            "  Ce paquet ne peut pas etre publie, et la connexion Google\n" +
            "  echouera si son empreinte n'est pas enregistree chez Firebase.\n")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}