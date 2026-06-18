# CMS2026 — Reference Flutter App (CMS-driven)

A **reference implementation** of a fully CMS-driven Flutter mobile app for
CMS2026. The app has **no hard-coded screens-list, menu or branding** — it reads
the CMS at runtime so a webmaster's choices in **Admin → Mobile App Builder**
(menu, home-page sections, branding) render directly in the app.

> **Status: uncompiled reference.** This code was authored against the documented
> CMS2026 mobile contract (`docs/mobile-template/README.md` §7) and is idiomatic,
> null-safe Flutter/Dart, but it has **not been compiled or run** — there is no
> Flutter SDK in the authoring environment. Run `flutter pub get` + `flutter
> analyze` before shipping; pin package versions to your toolchain.

> **Phase 6f — Enterprise Runtime wiring (added).** The app is now fully
> **CMS-driven at runtime**: it pulls feature flags / remote config / A/B
> experiments / a resolved theme from `GET /api/runtime/config` (ETag + 304),
> registers the device + FCM token, handles push taps → deep links, routes
> Universal/App Links, caches content with delta sync + an offline form queue +
> server-synced favorites, and emits an analytics event stream with session +
> screen tracking — all server-controlled, **no rebuild**. Everything degrades
> gracefully when the new endpoints / Firebase / biometrics are absent (the app
> still boots + runs exactly as the pre-6f read-only reference). See
> **§ Runtime wiring (Phase 6f)** below and `docs/mobile-template/flutter-runtime-wiring.md`.

---

## How it becomes "CMS-driven"

At startup the app loads `assets/config/app_config.json` (the CI injects the
CMS-generated config — the byte-for-byte output of the backend
`AppConfigBuilder` — here at build time). That config now carries the **app
identity, branding, baseUrl, navigation style, and the per-app menu + home
layout baked right in** (so the app paints instantly, offline-first). It then
OTA-refreshes the menu + home from the API for live changes:

| Concern | Source | Consumed by |
|---|---|---|
| Identity / branding / `navigation.style` | `app_config.json` (`app`, `branding`, `navigation`) | `lib/core/app_config.dart`, `lib/theme/`, `lib/nav/main_scaffold.dart` |
| Drawer / bottom-nav items | baked `modules[]` **then** `GET /api/mobile/menu?app=&lang=` | `lib/nav/main_scaffold.dart`, `app_drawer.dart`, shortcuts |
| Home sections (ordered) | baked `home[]` **then** `GET /api/mobile/home-layout?app=&lang=` | `lib/home/home_screen.dart` (`HomeFeed`) |

**Per-app fetch.** `app.appId` from the baked config is sent as `?app=` on the
menu + home-layout calls, so each built app resolves **its own** menu/home rows
(falling back to the CMS global defaults when the app owns none — see the
backend `MobileLayoutResolver`). The shell ([`MainScaffold`](lib/nav/main_scaffold.dart))
is the single owner of this data: it seeds from the baked config (instant first
paint), kicks off the OTA refresh, and **degrades back to the baked data on any
network error** so the app is never blank.

All API responses use the unified envelope
`{ success, statusCode, message, data, errors, pagination }`; the client unwraps
`data` (and `data.items` for paged lists). See `lib/core/api_client.dart`.

### Navigation style (`navigation.style`)

The baked `navigation.style` decides the app chrome; `MainScaffold` switches on it:

| `style` | Behaviour |
|---|---|
| `drawer` | Hamburger [`Drawer`](lib/nav/app_drawer.dart) only (default / fallback). |
| `bottomnav` | A `BottomNavigationBar` built from the first ~5 menu items (Home + modules); **no** drawer. A language menu moves to the AppBar. |
| `both` | Drawer **and** bottom-nav. |

Bottom-nav tabs use a hub pattern: tab 0 is the home feed; other tabs push their
menu `route` and snap back to Home on return — reusing the existing full-screen
routes without nesting Scaffolds.

### Home section type → widget → data source (README §7.2 — all 20 types)

The section factory is `sectionFor(section, …)` in `home_screen.dart`. An
**unknown `type` is skipped gracefully** (renders nothing), so the CMS can add
new section types without breaking older app builds.

| `type` | Widget (`lib/home/sections/`) | Config keys | CMS data source |
|---|---|---|---|
| `slider` | `slider_section.dart` (PageView carousel, autoplay) | `linkGroupKey`, `autoplay?`, `interval?` | `GET /api/links/by-group-key/{linkGroupKey}` |
| `news` | `news_section.dart` (horizontal cards → detail) | `categoryId?`, `count` | `GET /api/news?categoryId=&pageSize=count` |
| `shortcuts` | `shortcuts_section.dart` (icon grid → routes) | `moduleNames[]` | items from `/api/mobile/menu` by `moduleNames[]` |
| `banner` | `banner_section.dart` | `imageUrl`, `link?` | static (from config) |
| `publications` | `generic_list_section.dart` | `count` | `GET /api/publications?pageSize=count` |
| `services` | `generic_list_section.dart` | — | `GET /api/companies/services` |
| `webview` | `webview_section.dart` (card → opens `url` in external browser) | `url` | `config.url` |
| `spacer` | `spacer_section.dart` | `height` | static gap |
| `announcements` | `announcements_section.dart` (list) | `count` | `GET /api/announcements?pageSize=count` |
| `gallery` | `gallery_section.dart` (cover tiles → `/gallery`) | `count` | `GET /api/gallery?pageSize=count` (albums) |
| `videos` | `videos_section.dart` (thumbnails → `/speeches`) | `count` | `GET /api/speeches?pageSize=count` |
| `events` | `news_section.dart` (event category) | `categoryId`, `count` | `GET /api/news?categoryId=&pageSize=count` |
| `faq` | `faq_section.dart` (accordion → `/faq`) | `count` | `GET /api/faq?pageSize=count` |
| `contact` | `contact_section.dart` (phone/email/address card) | `phone?`, `email?`, `address?` | `GET /api/settings/public` (+ config overrides) |
| `sociallinks` | `social_links_section.dart` (icon row) | `linkGroupKey` | `GET /api/links/by-group-key/{linkGroupKey}` |
| `search` | `search_section.dart` (tappable bar → `SearchScreen`) | — | — (screen queries `/api/search/semantic`) |
| `html` | `html_section.dart` (cleaned HTML via `HtmlText`) | `html` | static |
| `hero` | `hero_section.dart` (single featured) | `newsId?` \| `imageUrl`,`title`,`link` | `GET /api/news/{newsId}` (when `newsId`) else static |
| `categories` | `categories_section.dart` (grid → news by category) | — | `GET /api/news/categories` |
| `about` | `about_section.dart` (page preview → `PageScreen`) | `pageKey` | `GET /api/pages/by-key/{pageKey}` |

> **Note:** `webview` sections (and the `/webview?url=` route) open the link in
> the **external browser** via `url_launcher`. The `webview_flutter` dependency
> was removed for build portability — its native Android plugin requires a newer
> Kotlin than the `flutter create`-scaffolded project uses in CI. Swap in
> `webview_flutter` (or `flutter_inappwebview`) if you need an embedded WebView
> and can manage the Android Kotlin/Gradle toolchain.

### Content detail / list endpoints

| Screen (`lib/screens/`) | Endpoint |
|---|---|
| `news_screen.dart` | `GET /api/news?categoryId=&pageSize=` |
| `news_detail_screen.dart` | `GET /api/news/{id}` |
| `publications_screen.dart` | `GET /api/publications?pageSize=` |
| `services_screen.dart` | `GET /api/companies/services` |
| `gallery_screen.dart` | `GET /api/gallery?pageSize=` (album grid) |
| `speeches_screen.dart` | `GET /api/speeches?pageSize=` (videos) |
| `faq_screen.dart` | `GET /api/faq?pageSize=` (accordion) |
| `search_screen.dart` | `GET /api/search/semantic?q=` → fallback `GET /api/news?search=` |
| `page_screen.dart` | `GET /api/pages/by-key/{key}` |
| `webview_screen.dart` | (opens `config.url` / `/webview?url=` in the external browser) |
| `placeholder_screen.dart` | (fallback for unknown routes) |

Menu `route` values resolved by `lib/routing/app_router.dart`:
`/news` · `/news/{id}` · `/news?categoryId=` · `/events` · `/publications` ·
`/services` · `/gallery` · `/speeches` (`/videos`) · `/faq` · `/search` ·
`/contact` · `/page/{key}` (`/about/{key}`) · `/webview?url=`. Unknown routes
fall back to a **CMS page lookup by key**, then a placeholder — navigation
never dead-ends.

---

## Project layout

```
flutter-reference/
├── pubspec.yaml                       # deps: http, cached_network_image, url_launcher, intl + (6f) app_links,
│                                      #   connectivity_plus, hive/hive_flutter, flutter_secure_storage, local_auth
├── analysis_options.yaml
├── assets/config/app_config.json      # sample (JSC branding, baked menu+home); CI overwrites at build time
├── .github/workflows/build.yml        # COPIED VERBATIM from docs/mobile-template/build.yml
└── lib/
    ├── main.dart                      # load config → RuntimeBootstrap.start() → MaterialApp (theme/locale/observers) → MainScaffold
    ├── core/
    │   ├── app_config.dart            # typed config model (nested `app`/baked `modules`/`home`/`navigation.style`) + AppConfig.load()
    │   ├── api_client.dart            # envelope-unwrapping client; +raw GET/POST (304/401 seams), bearer/device headers, security hooks
    │   ├── models.dart                # MenuItem, HomeSection, NewsItem, LinkItem, Publication, ServiceItem, PageContent, …
    │   ├── runtime/runtime_models.dart # RuntimeContext + RuntimeConfig envelope (flags/config/experiments/theme/etag)
    │   ├── storage/cache_service.dart  # Hive kv/collections/formQueue/favorites (in-memory fallback)
    │   └── services/                   # Phase-6f runtime services + the bootstrap composition root
    │       ├── runtime_bootstrap.dart  #   ordered wiring: config→flags/theme→device→push→deeplinks→sync+analytics
    │       ├── runtime_service.dart     #   GET /api/runtime/config (ETag/304) + typed flag/config/experiment/theme accessors
    │       ├── device_service.dart      #   POST /api/devices/{register,heartbeat,topics}
    │       ├── push_service.dart        #   pluggable PushProvider (no-op default) → tap → deeplink + click
    │       ├── deeplink_service.dart    #   app_links → /api/deeplink/resolve → Navigator.pushNamed
    │       ├── sync_service.dart        #   /api/sync/{manifest,delta,downloads,favorites,forms/submit}
    │       ├── analytics_service.dart   #   POST /api/analytics/events queue+flush + session/screen NavigatorObserver
    │       └── auth_service.dart        #   secure token storage + device id + 401-refresh + biometric (local_auth)
    ├── theme/app_theme.dart           # ThemeData from tokens/branding; `fromConfigWithRuntime` applies runtime theme.mode
    ├── nav/
    │   ├── main_scaffold.dart         # app shell: navigation.style switch (drawer|bottomnav|both), baked-first + OTA refresh
    │   └── app_drawer.dart            # drawer from menu; icon-name → IconData; language switcher
    ├── home/
    │   ├── home_screen.dart           # HomeFeed (presentational) + sectionFor() factory for all 20 types
    │   └── sections/                  # one widget per section type (16 widgets cover the 20 types)
    ├── routing/app_router.dart        # route table; unknown → page-by-key → placeholder
    ├── screens/                       # news, news detail, publications, services, gallery, speeches, faq, search, page, webview, placeholder
    └── shared/                        # icon_map.dart, section_header.dart, html_text.dart, format.dart
```

---

## `app_config.json` shape (injected by CI — baked per-app)

The CI writes the backend `AppConfigBuilder` output verbatim. It nests identity
under `app`, carries `navigation.style`, and **bakes this app's `modules[]` and
`home[]`** so the app renders instantly before any network call:

```jsonc
{
  "app":   { "appId": "com.jsc.app", "appName": "…", "bundleId": "…",
             "versionName": "1.0.0", "versionCode": 1 },
  "api":   { "baseUrl": "https://your-cms-host", "mobileEndpoint": "/mobile", "timeout": 30000 },
  "branding":   { "primaryColor": "#2F7995", "secondaryColor": "#1D586F", "accentColor": "#E8A33D",
                  "themeMode": "light", "logoUrl": "…", "splashUrl": "…", "fontFamily": "Cairo" },
  "navigation": { "style": "drawer" | "bottomnav" | "both" },
  "modules":    [ { "name": "news", "enabled": true, "icon": "newspaper",
                    "route": "/news", "displayOrder": 2, "titleAr": "الأخبار", "titleEn": "News" } ],
  "home":       [ { "type": "slider", "title": "أبرز الأخبار", "order": 1,
                    "config": { "linkGroupKey": "home_slider" } } ],
  "languages":  { "default": "ar", "supported": ["ar","en"], "rtlLanguages": ["ar"] },
  "features":   { "pushNotifications": true, "darkMode": false, "offlineMode": true, "inAppFeedback": true }
}
```

`AppConfig.fromJson` is fully defensive: every field is read from both the
nested (baked) and the legacy/flat location, and any missing field falls back to
a safe default so a partial config never crashes startup. The baked `modules[]`
and `home[]` seed the first paint; the API OTA-refresh then replaces them.

---

## Use this as a template (Admin → Templates)

1. Push this folder to its own GitHub repo (or use it as
   `github.com/ramiasaad-svg/cms2026-mobile-template`). It already contains
   `.github/workflows/build.yml` and reads `assets/config/app_config.json`, and
   it renders the menu + home from the §7 contract.
2. **Admin → Mobile App Builder → القوالب (Templates) → "إضافة قالب"**: paste the
   repo URL + branch + Flutter version (3.24.0) + a preview image, mark **Active**.
3. In an app config (Mobile App Builder → edit app), pick this template. The next
   **Trigger Build** dispatches `build.yml` in this repo with the CMS-generated
   `app_config.json`, producing APK / AAB / IPA artifacts the CMS downloads.

Keep `pubspec.yaml`'s `environment.flutter` in sync with `build.yml`'s
`env.FLUTTER_VERSION` (both `3.24.0`).

---

## Runtime wiring (Phase 6f)

The on-device consumption side of the Enterprise Mobile Runtime (the backend
planes are Phase 6a–6e). All services live in `lib/core/services/` and are
composed by `RuntimeBootstrap` (`runtime_bootstrap.dart`), wired into
`main.dart` in this order: **config → runtime flags/theme → device register →
push → deep links → sync + analytics**. Each step is independently guarded so a
missing capability never blocks startup.

| Service (`lib/core/services/`) | Consumes (CMS endpoint) | What it does |
|---|---|---|
| `runtime_service.dart` | `GET /api/runtime/config` (ETag + `If-None-Match` → 304) | Builds the `RuntimeContext` { deviceId, platform, appVersion, locale, uid, role, campaign, segments }, fetches the envelope, caches it (offline-safe), exposes `flagBool` / `configX` / `experimentVariant` / `theme`. Gates UI + applies the theme mode. |
| `device_service.dart` | `POST /api/devices/{register,/{id}/heartbeat,/{id}/topics}` | Upserts the device (token optional), periodic heartbeat, topic sync. |
| `push_service.dart` | `POST /api/push/track/click` (+ FCM) | Pluggable `PushProvider` (default **no-op** → builds with no Firebase). Foreground / background / terminated handlers → notification tap parses its deep link → navigates (same path as #deeplinks) + reports the click. |
| `deeplink_service.dart` | `GET /api/deeplink/resolve` (+ `app_links`) | Universal/App Links + custom-scheme → in-app route (path map, else server resolve) → `Navigator.pushNamed` (the named routes `app_router.dart` already resolves). |
| `cache_service.dart` + `sync_service.dart` | `GET /api/sync/{manifest,delta,downloads,favorites}` · `POST /api/sync/{forms/submit,favorites}` | Manifest → precache to Hive; delta sync with a persisted cursor (upserts + tombstones); idempotent **offline form queue** (`clientSubmissionId`, flush on reconnect); **favorites** mirror (LWW). `connectivity_plus` triggers flush on reconnect. |
| `analytics_service.dart` | `POST /api/analytics/events` | Local event queue → **batch flush** (`{ events:[…], appId, platform, appVersion }`), honouring consent + `flags.analytics.enabled` + `config.analytics.sampleRate`. Auto session (`session_start`/`session_end` + `sessionId`) + `screen_view` via a `NavigatorObserver`; helpers for click/search/download/form_submit carrying the current experiment assignments. |
| `auth_service.dart` | (token endpoints — 6g) | Stable device id + secure token storage (`flutter_secure_storage`), token-refresh-on-401 seam, optional biometric unlock (`local_auth`) gated by `config.session.biometric`. |

The shared `ApiClient` (`api_client.dart`) carries the bearer token + device id,
exposes raw `getRaw`/`postJsonRaw` (with the 304 + 401-retry seams), and holds
two **security hooks** (`ApiSecurityHooks`): a request-signing seam and a
cert-pinning client factory — both no-ops until **6g** supplies keys.

### Native config for deep links (Universal / App Links)

`app_links` receives the link, but the OS only delivers Universal/App Links when
the native association is in place. The backend already serves the association
files (`WellKnownController`): `/.well-known/apple-app-site-association` and
`/.well-known/assetlinks.json` (from `config.deeplink.*`). The app side needs:

- **iOS (Universal Links)** — add the Associated Domains entitlement
  `applinks:YOUR_DOMAIN` in `ios/Runner/Runner.entitlements` + enable the
  capability in Xcode. Host the AASA at `https://YOUR_DOMAIN/.well-known/apple-app-site-association`
  (the CMS serves it with `Content-Type: application/json`, no extension).
- **Android (App Links)** — add an `intent-filter` with
  `android:autoVerify="true"` for `https://YOUR_DOMAIN` (+ your custom scheme)
  to the launcher activity in `android/app/src/main/AndroidManifest.xml`, and
  host `https://YOUR_DOMAIN/.well-known/assetlinks.json` with the release
  keystore's SHA-256 fingerprint (set `config.deeplink.androidSha256`).
- **Custom scheme** (fallback / dev) — register a scheme (e.g. `jscapp://`) in
  the same manifest/Info.plist; `routeForUri` handles `scheme://news/15` too.

> The CI `build.yml` scaffolds `android/` + `ios/` from `pubspec.yaml` via
> `flutter create` when they're absent — that generates the base manifest /
> Info.plist with the app links plugin entries; add the domain-specific
> entitlement + intent-filter above for production verification.

### Enabling Push (Firebase)

Push ships **disabled** (the default `NoOpPushProvider`) so the app builds with
no Firebase config — the CI build stays green. To enable it:

1. Add `firebase_core` + `firebase_messaging` to `pubspec.yaml` and drop in
   `google-services.json` (Android) / `GoogleService-Info.plist` (iOS).
2. Implement a `FirebasePushProvider implements PushProvider` mapping FCM's
   `getToken()` / `onTokenRefresh` / `onMessage` / `onMessageOpenedApp` /
   `getInitialMessage()` to the `PushMessage` shape (read `deepLink` +
   `campaignId` from `message.data`).
3. Pass it to `RuntimeBootstrap(pushProvider: FirebasePushProvider())` in
   `main.dart`. Nothing else changes — registration, topic sync, tap→deeplink
   and click reporting are already wired.

## Notes / honest limitations

- **Not compiled here.** Idiomatic and contract-accurate, but run `flutter pub
  get` + `flutter analyze` (and bump package versions to your channel) before a
  real build.
- **HTML content** (news/page bodies) is rendered as cleaned plain text via
  `lib/shared/html_text.dart`. For full markup/images, swap in `flutter_html`
  or `flutter_widget_from_html` and replace the `HtmlText` widget.
- **Enums** (`status`, link `target`) come from the API as integers (ASP.NET
  Core default serialization, no `JsonStringEnumConverter`). They aren't needed
  for rendering, so models ignore them; parse defensively if you start using
  them.
- **Push / Firebase / biometric auth / offline cache / analytics** are now
  **wired** (Phase 6f — see the section below), gated by both the baked
  `features` flags (`pushNotifications`, `offlineMode`, `biometricAuth`,
  `analytics`, …) AND the runtime envelope's flags. Push is behind a pluggable
  provider whose default is a no-op (so the app builds with NO Firebase); add
  `firebase_messaging` + a `FirebasePushProvider` to light it up.
- **`contact` info** is read from `GET /api/settings/public` (a flat Key→Value
  map). The exact setting keys vary per install — the section probes several
  common keys (`phone`/`contactPhone`, `email`/`contactEmail`,
  `address`/`contactAddress`) and the section `config` can override them
  directly. Adjust the keys to match your settings.
- **Search** uses `GET /api/search/semantic?q=` (vector search); when that is
  unavailable (embeddings not configured) it transparently falls back to a
  keyword news search (`GET /api/news?search=`).
- The bundled `app_config.json` uses `https://REPLACE_WITH_CMS_HOST` — the CI
  overwrites it from `AppBuild.AppConfigSnapshot`, so it's only a dev placeholder.
```
