# Football display translations

The canonical vocabulary is football-catalog.json. API/admin share football.js.
The browser bundle and Flutter catalogue are generated:

    node backend/scripts/generate-football-translations.cjs
    node backend/scripts/generate-football-translations.cjs --check

Run these from the repository root. npm test in both services checks drift.
Flutter implements the same bounded display grammar; shared fixtures in
backend/src/__tests__/fixtures/football-translations.json test both implementations.

Keep raw provider names, market values, numeric thresholds and settlement keys.
Add explicit aliases for known provider variations; never guess unknown markets.
Do not merge whole-match and first/second-half markets. Countries apply only to
country/team fields, not arbitrary player names. Unknown text is returned intact.

Admin shows FR/EN previews and terms needing review in the publication form.
Custom analyst prose is not machine-translated or rewritten in the database.
Advice has an additive advice_en field; clients retain the existing French field
for older server responses. Mobile changes require a new application release.

## Bilingual editorial content and notifications

Nullable English fields accompany the original fields for predictions, analyst
notes, tutorial titles/descriptions/articles, news titles/summaries/articles and
notification titles/bodies. The admin forms accept both languages; absence
preserves an existing translation on update and an explicitly blank field clears
it. Unknown prose, external RSS articles and user content are never guessed.
Existing editorial content needs an English version entered by an editor.

The mobile client retains both languages in its cache and chooses at display
time. This includes favourites, recommendations and bankroll prediction labels.
Personalised recommendation reasons are also emitted in both languages.
Locked predictions and premium tutorial bodies are restricted server-side in
both languages; a translated field must never bypass an entitlement check.

Notification templates use notification-catalog.json. Custom campaigns accept
an optional complete title/body English pair. Devices register their language;
personal and segmented sends partition tokens by language. Public topics keep
the existing French name and append _en for English. The mobile app leaves the
other language topic when switching. Preference opt-outs still apply. The inbox
retains both languages; old known system templates are translated on read.

Admin navigation and shared actions use admin-web/lib/ui.en.json. A language
selector stores a whitelisted cookie, independent of the mobile language.
Keep translations explicit through tAdmin/uiText: do not translate user data,
API identifiers or arbitrary DOM text. Some detailed operational copy and
dynamic validation messages remain French and need further catalogue entries.

## Release order

1. Back up the database and validate this release on staging.
2. Apply Prisma migration 20261007120000_bilingual_content before deploying code
   that selects the new columns. It only adds nullable content fields and a
   French-default device language; existing values are preserved.
3. Generate the Prisma client, build the backend and restart backend/admin.
4. Publish the Flutter build. Older clients keep the original fields/topics.
5. Verify on real FR/EN devices: login, language switch, favourite match alerts,
   campaign, inbox, article fallback, premium access and token renewal.

No migration, push delivery or production deployment is performed by the tests.
Push tests use a mocked Firebase transport. Platform delivery requires a real
device check before release.

## Checks

Backend: football_translations, bilingual_delivery, bilingual_tutorials,
notification_topic and premium_gating Jest suites, plus TypeScript compilation.
Admin: npm test includes generated-catalog drift, real form previews and all
view fixtures in French/English (_check_interface_bilingue.js).
Mobile: editorial_translations_test, football_translations_test,
localization_test and app_notification_test.
