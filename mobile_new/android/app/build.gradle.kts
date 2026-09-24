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

    // ─── Variantes de distribution ───────────────────────────────────────────
    //
    // Le canal ne se limite pas a du code Dart : la variante « direct »
    // telecharge et installe elle-meme ses mises a jour, ce qui exige
    // REQUEST_INSTALL_PACKAGES. Cette permission ne doit jamais figurer dans le
    // paquet publie sur Google Play — la politique « Device and Network Abuse »
    // reserve l'installation d'APK hors Play aux boutiques d'applications, et
    // la declarer ailleurs n'est pas une mise a jour refusee mais un motif de
    // retrait.
    //
    // Un `--dart-define` ne peut rien ici : il ne change pas le manifeste. Il
    // faut deux variantes, dont une seule fusionne
    // `src/direct/AndroidManifest.xml`.
    //
    // Consequence pour le developpement : `flutter run` exige desormais
    // `--flavor direct`. `tool/build.ps1` s'en charge pour les releases.
    flavorDimensions += "canal"

    productFlavors {
        create("direct") { dimension = "canal" }
        create("play")   { dimension = "canal" }
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
 * APK par architecture (constat M3) : même versionCode que l'APK universel.
 *
 * Avec `--split-per-abi`, Flutter numérote chaque architecture à part :
 * 1000 + versionCode pour armeabi-v7a, 2000 + versionCode pour arm64-v8a.
 * Un téléphone mis à jour par l'APK arm64 (2017) refusait ensuite l'APK
 * universel du site (18) comme une rétrogradation — « Application non
 * installée ». Hors de Google Play, rien n'exige des numéros distincts : un
 * seul numéro par version rend les trois APK interchangeables.
 *
 * Inscrit après le greffon Flutter, ce rappel passe après le sien.
 */
android.applicationVariants.all {
    val variante = this
    outputs.all {
        (this as com.android.build.gradle.internal.api.ApkVariantOutputImpl)
            .versionCodeOverride = variante.versionCode
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