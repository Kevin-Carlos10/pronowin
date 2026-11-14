import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'catalog_en.dart';

/// Explicit UI translations. French messages are the source keys, as in gettext.
/// API fields, user content, team names and stored values must not be translated.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  static const supportedLocales = [Locale('fr'), Locale('en')];
  static const delegate = _AppStringsDelegate();

  static String normaliseLanguage(String? language) =>
      language?.trim().toLowerCase().split(RegExp('[-_]')).first == 'en'
      ? 'en'
      : 'fr';

  /// La langue choisie dans l'app, ou à défaut celle du téléphone.
  ///
  /// Sans choix enregistré, l'app démarrait en français même sur un téléphone
  /// réglé en anglais : l'anglophone devait trouver seul le réglage. Un choix
  /// fait dans l'app l'emporte toujours ; les autres langues donnent le
  /// français.
  ///
  /// Lue par la liaison Flutter (initialisée avant le premier appel), pour
  /// que les tests puissent simuler la langue du téléphone.
  static String languePreferee(String? choisie, [Locale? appareil]) =>
      normaliseLanguage(
        choisie ??
            (appareil ?? WidgetsBinding.instance.platformDispatcher.locale)
                .languageCode,
      );

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('fr'));

  /// For services without a widget context. Set before startup and whenever the
  /// saved language changes. Widgets should use [of] so they rebuild immediately.
  static AppStrings get current =>
      AppStrings(Locale(normaliseLanguage(Intl.defaultLocale)));
  static void setCurrentLanguage(String language) {
    Intl.defaultLocale = normaliseLanguage(language);
  }

  String text(String source, [List<Object?> arguments = const []]) {
    final template = locale.languageCode == 'en'
        ? englishMessages[source] ?? source
        : source;
    // One pass: a user value containing another placeholder remains untouched.
    return template.replaceAllMapped(RegExp(r'\{arg(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? '${arguments[index]}' : match[0]!;
    });
  }

  String count(int count, {required String one, required String other}) => text(
    (locale.languageCode == 'fr' ? count == 0 || count == 1 : count == 1)
        ? one
        : other,
    [count],
  );
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => ['fr', 'en'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

String tr(
  BuildContext context,
  String source, [
  List<Object?> arguments = const [],
]) => AppStrings.of(context).text(source, arguments);

String trCurrent(String source, [List<Object?> arguments = const []]) =>
    AppStrings.current.text(source, arguments);
