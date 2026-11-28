import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';

import 'package:pronowin/core/services/apk_par_abi.dart';

/// La mise à jour intégrée télécharge l'APK de l'architecture du téléphone
/// (constat M3 : 68 Mo pour l'universel, 25 pour l'arm64 seul).
void main() {
  const universel = 'https://pronowin.space/downloads/app-release.apk';
  const parAbi = {
    'arm64-v8a':   'https://pronowin.space/downloads/pronowin-arm64-v8a.apk',
    'armeabi-v7a': 'https://pronowin.space/downloads/pronowin-armeabi-v7a.apk',
  };

  test('les architectures Android portent leur nom Android', () {
    expect(abiAndroid(Abi.androidArm64), 'arm64-v8a');
    expect(abiAndroid(Abi.androidArm), 'armeabi-v7a');
    expect(abiAndroid(Abi.androidX64), 'x86_64');
    expect(abiAndroid(Abi.windowsX64), isNull);
  });

  test('un téléphone arm64 prend l\'APK arm64, un 32 bits le sien', () {
    expect(lienApkPour(universel: universel, parAbi: parAbi, abi: 'arm64-v8a'), parAbi['arm64-v8a']);
    expect(lienApkPour(universel: universel, parAbi: parAbi, abi: 'armeabi-v7a'), parAbi['armeabi-v7a']);
  });

  test('sans APK pour son architecture, ou sans liste, l\'universel', () {
    expect(lienApkPour(universel: universel, parAbi: parAbi, abi: 'x86_64'), universel);
    expect(lienApkPour(universel: universel, parAbi: null, abi: 'arm64-v8a'), universel);
    expect(lienApkPour(universel: universel, parAbi: const <String, dynamic>{}, abi: 'arm64-v8a'), universel);
    expect(lienApkPour(universel: universel, parAbi: parAbi, abi: null), universel);
  });

  test('un lien qui n\'est pas en https n\'est pas suivi', () {
    expect(lienApkPour(universel: universel,
        parAbi: const {'arm64-v8a': 'http://pronowin.space/a.apk'}, abi: 'arm64-v8a'), universel);
  });
}
