import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pronowin/l10n/app_strings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/dio_client.dart';

// ─── Clés SharedPreferences ───────────────────────────────────────────────────
const _kTheme         = 'settings_theme';
const _kLang          = 'settings_lang';
const _kNotifMatch    = 'notif_match';
const _kNotifPromo    = 'notif_promo';
const _kNotifReferral = 'notif_referral';
const _kNotifPremium  = 'notif_premium';
const _kPinEnabled    = 'security_pin_enabled';
const _kBioEnabled    = 'security_bio_enabled';
/// « Tout mettre en pause » (11 novembre 2026) : en pause, et les quatre
/// réglages d'avant, à rendre à la reprise (« 1011 »).
const _kNotifPause      = 'notif_pause';
const _kNotifAvantPause = 'notif_avant_pause';

// ─── Topics FCM correspondants ────────────────────────────────────────────────
const _topicMatch    = 'match_alerts';
const _topicPromo    = 'promo_alerts';
const _topicReferral = 'referral_alerts';
const _topicPremium  = 'premium_alerts';

// ─── Modèle ───────────────────────────────────────────────────────────────────
class AppSettings {
  final ThemeMode themeMode;
  final String    lang;
  final bool      notifMatch, notifPromo, notifReferral, notifPremium;
  final bool      pinEnabled, bioEnabled;
  /// Thème Nocturne : le sombre sur du noir pur (avec [themeMode] sombre).
  final bool      nocturne;
  /// Toutes les notifications en pause : les quatre catégories sont coupées
  /// jusqu'à la reprise, qui rend les réglages d'avant.
  final bool      notifPause;

  const AppSettings({
    this.themeMode     = ThemeMode.dark,
    this.lang          = 'fr',
    this.notifMatch    = true,
    this.notifPromo    = false,   // marketing : opt-in
    this.notifReferral = true,
    this.notifPremium  = true,
    this.pinEnabled    = false,
    this.bioEnabled    = false,
    this.nocturne      = false,
    this.notifPause    = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode, String? lang,
    bool? notifMatch, bool? notifPromo, bool? notifReferral,
    bool? notifPremium,
    bool? pinEnabled, bool? bioEnabled, bool? nocturne, bool? notifPause,
  }) => AppSettings(
    themeMode:     themeMode     ?? this.themeMode,
    lang:          lang          ?? this.lang,
    notifMatch:    notifMatch    ?? this.notifMatch,
    notifPromo:    notifPromo    ?? this.notifPromo,
    notifReferral: notifReferral ?? this.notifReferral,
    notifPremium:  notifPremium  ?? this.notifPremium,
    pinEnabled:    pinEnabled    ?? this.pinEnabled,
    bioEnabled:    bioEnabled    ?? this.bioEnabled,
    nocturne:      nocturne      ?? this.nocturne,
    notifPause:    notifPause    ?? this.notifPause,
  );

  String get themeName {
    switch (themeMode) {
      case ThemeMode.dark:   return nocturne ? trCurrent("Nocturne") : trCurrent("Sombre");
      case ThemeMode.light:  return trCurrent("Clair");
      case ThemeMode.system: return trCurrent("Système");
    }
  }
  String get langName => lang == 'en' ? 'English' : 'Français';
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class SettingsNotifier extends StateNotifier<AppSettings> {
  final Ref _ref;
  SettingsNotifier(this._ref) : super(AppSettings(
        lang:      _ref.read(initialLanguageProvider),
        themeMode: _ref.read(initialThemeModeProvider),
        nocturne:  _ref.read(initialNocturneProvider),
      )) {
    ready = _load();
  }

  late final Future<void> ready;

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  // ─── Chargement initial ───────────────────────────────────────────────────
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = AppSettings(
      themeMode:     _themeChanged ? state.themeMode : themeDepuisPreference(p.getString(_kTheme)),
      lang:          _languageChanged ? state.lang : AppStrings.languePreferee(p.getString(_kLang)),
      notifMatch:    p.getBool(_kNotifMatch)    ?? true,
      // Marketing : consentement explicite. Les alertes de match, le
      // parrainage et l'abonnement sont du service attendu et restent
      // actifs ; les offres commerciales se choisissent.
      notifPromo:    p.getBool(_kNotifPromo)    ?? false,
      notifReferral: p.getBool(_kNotifReferral) ?? true,
      notifPremium:  p.getBool(_kNotifPremium)  ?? true,
      pinEnabled:    p.getBool(_kPinEnabled)    ?? false,
      bioEnabled:    p.getBool(_kBioEnabled)    ?? false,
      nocturne:      _themeChanged ? state.nocturne : p.getString(_kTheme) == 'nocturne',
      notifPause:    p.getBool(_kNotifPause)    ?? false,
    );

    AppStrings.setCurrentLanguage(state.lang);

    // Synchroniser les topics FCM avec les préférences sauvegardées
    unawaited(_syncAllTopics(state));
    unawaited(_syncLanguage());
  }

  // ─── Synchroniser tous les topics au démarrage ────────────────────────────
  Future<void> _syncAllTopics(AppSettings s) async {
    await _setTopic(_topicMatch,    s.notifMatch);
    await _setTopic(_topicPromo,    s.notifPromo);
    await _setTopic(_topicReferral, s.notifReferral);
    await _setTopic(_topicPremium,  s.notifPremium);
  }

  // ─── S'abonner ou se désabonner d'un topic FCM ───────────────────────────
  Future<void> _setTopic(String topic, bool subscribe) async {
    try {
      final selected = state.lang == 'en' ? '${topic}_en' : topic;
      final other = state.lang == 'en' ? topic : '${topic}_en';
      await _fcm.unsubscribeFromTopic(other);
      if (subscribe) {
        await _fcm.subscribeToTopic(selected);
        debugPrint('[FCM Topics] ✅ Abonné à : $topic');
      } else {
        await _fcm.unsubscribeFromTopic(selected);
        debugPrint('[FCM Topics] 🔕 Désabonné de : $topic');
      }
    } catch (e) {
      debugPrint('[FCM Topics] Erreur pour $topic : $e');
    }
  }

  // ─── Thème ────────────────────────────────────────────────────────────────
  bool _themeChanged = false;

  /// [nocturne] : le sombre sur du noir pur ; sans effet hors du sombre.
  Future<void> setTheme(ThemeMode mode, {bool nocturne = false}) async {
    _themeChanged = true;
    final noir = mode == ThemeMode.dark && nocturne;
    state = state.copyWith(themeMode: mode, nocturne: noir);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, noir
        ? 'nocturne'
        : mode == ThemeMode.dark ? 'dark'
        : mode == ThemeMode.light ? 'light' : 'system');
  }

  // ─── Langue ───────────────────────────────────────────────────────────────
  bool _languageChanged = false;
  Future<void> _languageWrite = Future.value();
  Future<void> setLang(String lang) {
    final language = AppStrings.normaliseLanguage(lang);
    _languageChanged = true;
    AppStrings.setCurrentLanguage(language);
    state = state.copyWith(lang: language);
    // Preserve the order of rapid selections; an old write must not win.
    _languageWrite = _languageWrite.catchError((Object _) {}).then((_) async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLang, language);
      await _syncAllTopics(state);
      await _syncLanguage();
    });
    return _languageWrite;
  }

  Future<void> _syncLanguage() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _ref.read(dioProvider).post('/notifications/register-token', data: {
          'fcm_token': token, 'language': state.lang,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        });
      }
    } catch (_) { /* Local preference is retained; token registration retries at startup. */ }
  }

  // ─── Toggle notification (local + FCM topic + serveur) ────────────────────
  Future<void> toggleNotif(String key) async {
    final p = await SharedPreferences.getInstance();
    bool? newVal;

    switch (key) {
      case 'match':
        newVal = !state.notifMatch;
        state = state.copyWith(notifMatch: newVal);
        await p.setBool(_kNotifMatch, newVal);
        await _setTopic(_topicMatch, newVal);

      case 'promo':
        newVal = !state.notifPromo;
        state = state.copyWith(notifPromo: newVal);
        await p.setBool(_kNotifPromo, newVal);
        await _setTopic(_topicPromo, newVal);

      case 'referral':
        newVal = !state.notifReferral;
        state = state.copyWith(notifReferral: newVal);
        await p.setBool(_kNotifReferral, newVal);
        await _setTopic(_topicReferral, newVal);

      case 'premium':
        newVal = !state.notifPremium;
        state = state.copyWith(notifPremium: newVal);
        await p.setBool(_kNotifPremium, newVal);
        await _setTopic(_topicPremium, newVal);
    }

    if (newVal != null) await _syncPrefToServer(key, newVal);
  }

  // ─── Tout mettre en pause ─────────────────────────────────────────────────
  /// Coupe les quatre catégories d'un geste, comme « Tout mettre en pause »
  /// de Threads ou le « Mode silencieux » de Sofascore (11 novembre 2026) ;
  /// la reprise rend les réglages d'avant la pause. Chaque catégorie passe
  /// par [toggleNotif] : topics FCM et serveur suivent, comme à la main.
  Future<void> mettreNotifsEnPause(bool pause) async {
    if (pause == state.notifPause) return;
    final p = await SharedPreferences.getInstance();
    const cles = ['match', 'promo', 'referral', 'premium'];
    bool valeur(String k) => switch (k) {
      'match' => state.notifMatch,
      'promo' => state.notifPromo,
      'referral' => state.notifReferral,
      _ => state.notifPremium,
    };
    if (pause) {
      await p.setString(_kNotifAvantPause, cles.map((k) => valeur(k) ? '1' : '0').join());
      state = state.copyWith(notifPause: true);
      await p.setBool(_kNotifPause, true);
      for (final k in cles) {
        if (valeur(k)) await toggleNotif(k);
      }
    } else {
      final avant = p.getString(_kNotifAvantPause) ?? '1011';
      state = state.copyWith(notifPause: false);
      await p.setBool(_kNotifPause, false);
      for (var i = 0; i < cles.length; i++) {
        final voulu = i < avant.length && avant[i] == '1';
        if (voulu != valeur(cles[i])) await toggleNotif(cles[i]);
      }
    }
  }

  /// Les topics FCM ne filtrent que les envois de masse. Les notifications
  /// personnelles (parrainage, premium, résultat d'un match favori) partent par
  /// token : se désabonner d'un topic ne les coupait pas. Le serveur doit donc
  /// connaître la préférence pour la respecter dans `sendToUser`.
  ///
  /// Volontairement silencieux : l'écran Paramètres est accessible en invité,
  /// où l'appel renvoie 401. Le réglage local reste appliqué dans tous les cas.
  Future<void> _syncPrefToServer(String key, bool value) async {
    try {
      await _ref.read(dioProvider).patch(
        '/profile/notification-prefs', data: {key: value});
    } catch (_) { /* hors ligne ou invité — la préférence locale suffit */ }
  }

  // ─── PIN / Bio ────────────────────────────────────────────────────────────
  Future<void> setPinEnabled(bool v) async {
    state = state.copyWith(pinEnabled: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPinEnabled, v);
  }

  Future<void> setBioEnabled(bool v) async {
    state = state.copyWith(bioEnabled: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBioEnabled, v);
  }

  // ─── Vider le cache ───────────────────────────────────────────────────────
  Future<void> clearCache() async {
    final p = await SharedPreferences.getInstance();

    // Sauvegarder les settings avant de tout effacer
    final backup = {
      _kTheme:         p.getString(_kTheme),
      _kLang:          p.getString(_kLang),
      _kNotifMatch:    p.getBool(_kNotifMatch),
      _kNotifPromo:    p.getBool(_kNotifPromo),
      _kNotifReferral: p.getBool(_kNotifReferral),
      _kNotifPremium:  p.getBool(_kNotifPremium),
      _kPinEnabled:    p.getBool(_kPinEnabled),
      _kBioEnabled:    p.getBool(_kBioEnabled),
      _kNotifPause:    p.getBool(_kNotifPause),
      _kNotifAvantPause: p.getString(_kNotifAvantPause),
    };

    await p.clear();

    // Restaurer les settings
    for (final e in backup.entries) {
      if (e.value is String)  await p.setString(e.key, e.value as String);
      if (e.value is bool)    await p.setBool(e.key,   e.value as bool);
    }
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────
final initialLanguageProvider = Provider<String>((ref) => 'fr');

/// Le thème enregistré, lu avant le premier écran — comme la langue.
///
/// Il était lu après coup, par `_load` : l'application démarrait donc en
/// sombre, puis basculait en clair une fraction de seconde plus tard chez
/// ceux qui avaient choisi le clair.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);

/// Le thème Nocturne enregistré, lu lui aussi avant le premier écran.
final initialNocturneProvider = Provider<bool>((ref) => false);

/// Le sombre de l'application : le bleu nuit, ou le noir pur (Nocturne).
final nocturneProvider = Provider<bool>((ref) => ref.watch(settingsProvider).nocturne);

/// `settings_theme` → [ThemeMode]. Sombre par défaut, comme à l'installation.
ThemeMode themeDepuisPreference(String? valeur) => switch (valeur) {
      'light'  => ThemeMode.light,
      'system' => ThemeMode.system,
      _        => ThemeMode.dark,
    };

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref));

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider).themeMode);

final localeProvider = Provider<Locale>(
  (ref) => Locale(ref.watch(settingsProvider).lang));

/// Version de l'app lue depuis le bundle natif.
///
/// Elle était écrite en dur (« v1.0.0 ») à trois endroits de l'écran
/// Paramètres : la ligne « À propos », le pied de page et la feuille « À
/// propos ». Trois valeurs à mettre à jour à chaque release, donc trois
/// occasions de diverger du numéro réellement publié.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}';
});
