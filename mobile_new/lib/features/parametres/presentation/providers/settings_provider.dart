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

  const AppSettings({
    this.themeMode     = ThemeMode.dark,
    this.lang          = 'fr',
    this.notifMatch    = true,
    this.notifPromo    = true,
    this.notifReferral = true,
    this.notifPremium  = true,
    this.pinEnabled    = false,
    this.bioEnabled    = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode, String? lang,
    bool? notifMatch, bool? notifPromo, bool? notifReferral,
    bool? notifPremium,
    bool? pinEnabled, bool? bioEnabled,
  }) => AppSettings(
    themeMode:     themeMode     ?? this.themeMode,
    lang:          lang          ?? this.lang,
    notifMatch:    notifMatch    ?? this.notifMatch,
    notifPromo:    notifPromo    ?? this.notifPromo,
    notifReferral: notifReferral ?? this.notifReferral,
    notifPremium:  notifPremium  ?? this.notifPremium,
    pinEnabled:    pinEnabled    ?? this.pinEnabled,
    bioEnabled:    bioEnabled    ?? this.bioEnabled,
  );

  String get themeName {
    switch (themeMode) {
      case ThemeMode.dark:   return 'Sombre';
      case ThemeMode.light:  return 'Clair';
      case ThemeMode.system: return 'Système';
    }
  }
  String get langName  => 'Français'; // Seul le français est disponible pour l'instant
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class SettingsNotifier extends StateNotifier<AppSettings> {
  final Ref _ref;
  SettingsNotifier(this._ref) : super(const AppSettings()) {
    _load();
  }

  final _fcm = FirebaseMessaging.instance;

  // ─── Chargement initial ───────────────────────────────────────────────────
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = AppSettings(
      themeMode:     p.getString(_kTheme) == 'light'
                      ? ThemeMode.light
                      : p.getString(_kTheme) == 'system'
                          ? ThemeMode.system
                          : ThemeMode.dark,
      lang:          p.getString(_kLang)  ?? 'fr',
      notifMatch:    p.getBool(_kNotifMatch)    ?? true,
      notifPromo:    p.getBool(_kNotifPromo)    ?? true,
      notifReferral: p.getBool(_kNotifReferral) ?? true,
      notifPremium:  p.getBool(_kNotifPremium)  ?? true,
      pinEnabled:    p.getBool(_kPinEnabled)    ?? false,
      bioEnabled:    p.getBool(_kBioEnabled)    ?? false,
    );

    // Synchroniser les topics FCM avec les préférences sauvegardées
    await _syncAllTopics(state);
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
      if (subscribe) {
        await _fcm.subscribeToTopic(topic);
        debugPrint('[FCM Topics] ✅ Abonné à : $topic');
      } else {
        await _fcm.unsubscribeFromTopic(topic);
        debugPrint('[FCM Topics] 🔕 Désabonné de : $topic');
      }
    } catch (e) {
      debugPrint('[FCM Topics] Erreur pour $topic : $e');
    }
  }

  // ─── Thème ────────────────────────────────────────────────────────────────
  Future<void> setTheme(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light ? 'light' : 'system');
  }

  // ─── Langue ───────────────────────────────────────────────────────────────
  Future<void> setLang(String lang) async {
    state = state.copyWith(lang: lang);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLang, lang);
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
