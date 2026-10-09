import 'dart:ffi' show Abi;

/// Quel APK télécharger pour la mise à jour intégrée (constat M3 de l'audit du
/// 24 septembre 2026).
///
/// L'APK universel pèse 68 Mo ; celui de la seule architecture arm64, 25. Pour
/// un public qui paie chaque mégaoctet — et une mise à jour déjà ratée faute
/// d'espace —, c'est 64 % de données en trop. Le serveur publie un lien par
/// architecture ; l'application prend le sien, et l'universel à défaut.

/// Le nom Android (`Build.SUPPORTED_ABIS`) de l'architecture sur laquelle
/// tourne l'application.
///
/// `Abi.current()` est l'architecture du code natif chargé : sur un téléphone
/// arm64, l'APK universel charge sa bibliothèque arm64. C'est donc bien celle
/// dont l'APK allégé doit hériter.
String? abiAndroid([Abi? abi]) => switch (abi ?? Abi.current()) {
  Abi.androidArm64 => 'arm64-v8a',
  Abi.androidArm   => 'armeabi-v7a',
  Abi.androidX64   => 'x86_64',
  _                => null,
};

/// Le lien de l'APK de [abi] s'il est publié, l'universel sinon.
///
/// Un lien qui n'est pas en https est ignoré : l'APK s'installe avec les
/// droits de l'application, il ne doit pas pouvoir être substitué en route.
String? lienApkPour({String? universel, Object? parAbi, String? abi}) {
  if (abi != null && parAbi is Map) {
    final propre = parAbi[abi];
    if (propre is String && propre.startsWith('https://')) return propre;
  }
  return universel;
}
