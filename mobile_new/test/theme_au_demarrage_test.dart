import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronowin/features/parametres/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aides/code_seul.dart';

/// Le thème choisi doit être celui du premier écran.
///
/// Il était lu après coup, de façon asynchrone, alors que l'état initial
/// valait toujours `ThemeMode.dark` : chez qui avait choisi le clair,
/// l'application s'ouvrait en sombre puis basculait. La langue, elle, était
/// déjà lue avant `runApp` — le thème suit maintenant le même chemin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les valeurs enregistrées se relisent', () {
    expect(themeDepuisPreference('light'), ThemeMode.light);
    expect(themeDepuisPreference('system'), ThemeMode.system);
    expect(themeDepuisPreference('dark'), ThemeMode.dark);
    // Rien d'enregistré : le thème d'installation.
    expect(themeDepuisPreference(null), ThemeMode.dark);
  });

  test('le premier état est déjà le thème enregistré', () {
    SharedPreferences.setMockInitialValues({'settings_theme': 'light'});
    final c = ProviderContainer(overrides: [
      initialThemeModeProvider.overrideWithValue(ThemeMode.light),
    ]);
    addTearDown(c.dispose);

    // Lu de façon synchrone, sans attendre le chargement des préférences :
    // c'est ce que voit le tout premier rendu.
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('main lit la préférence avant le premier écran', () {
    final main = File('lib/main.dart').readAsStringSync().pipeCodeSeul();
    expect(main, contains("themeDepuisPreference(prefs.getString('settings_theme'))"));
    expect(main, contains('initialThemeModeProvider.overrideWithValue('));
  });
}
