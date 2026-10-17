# Mobile languages

The application supports French (default) and English. The choice is stored in
`settings_lang`, restored before the first frame and applied without recreating
the router or clearing user data.

## Adding UI messages

Use `tr(context, 'French source message')` in widgets. This registers a dependency
on Flutter Localizations, so open screens update when the language changes.
Add the English value in `en.json`, then run:

    dart run tool/generate_translations.dart

Use numbered placeholders for variable content:

    tr(context, 'Erreur : {arg0}', [details])

Do not interpolate variables in the lookup key. Use complete sentences instead
of joining translated fragments. For services with no BuildContext, use
`trCurrent`; it reads the locale installed at startup by settings. Do not store
translated display labels as API enum values, filter keys or persistent data.
Constant display models are translated at their presentation boundary.

Use `AppStrings.of(context).count(n, one: '{arg0} match', other: '{arg0} matchs')`
for counts, with both messages present in the catalogue. English uses the plural
for zero, and irregular plurals such as `matches` are translated as complete
messages. Do not construct plurals by adding a French suffix.

French remains the fallback for unknown messages/locales. Adding another
language requires a new catalogue, delegate locale, and picker option.

## Content supplied by the server

Known football markets, selections, countries, rounds, absences and transfers use
football_labels.dart and the generated shared football catalogue. Display labels
follow FR/EN; raw values remain unchanged. Run the backend generator and both
football translation test suites when extending the vocabulary.

Analyst notes, custom predictions, tutorial bodies and news support optional
English fields supplied by the server. editorial_text.dart selects English when
present, otherwise the original. Cache serialization preserves both originals.
Editors enter English content in admin; neither arbitrary prose, RSS nor user
comments are automatically machine-translated.

Notifications carry both languages in data and the inbox. FCM token registration
includes the device language; settings migrate public and favourite subscriptions
between the original French topic and its _en counterpart. Failed offline sync
retains the local preference and is retried on startup. Backend deployment and
the bilingual content migration must precede the new mobile release.

Do not translate arbitrary user data or hide a server message by replacing it
with a generic message. Keep account/purchase state, currency and stake rules
independent of the selected language.

## Verification

`flutter test test/localization_test.dart` checks catalogue consistency,
placeholder safety, language persistence, switching on the real settings screen,
the welcome screens, English match cards at 320 px with enlarged text, and that
switching languages leaves stored tutorial data unchanged.

A new mobile build is required to deliver these bundled translations. See
backend/src/i18n/README.md for migration and server/admin deployment order.
No app version or publication setting is changed by the translation work.
The editorial translation test also verifies cached sources, language changes,
recommendations, bankroll labels and notification read-state preservation.
