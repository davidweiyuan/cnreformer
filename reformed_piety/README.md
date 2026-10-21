# Reformed Piety · 歸正靈命塑造

Flutter successor to the CNReformer SwiftUI prototype. iPhone/iPad are the first release target; Android scaffolding shares the same Dart implementation but has not been built or device-tested yet.

## Run locally

Flutter 3.47.7 / Dart 3.13.5 were used for this checkout. SDK installed locally at `/Users/davidweiyuan/development/flutter`; no global shell configuration was changed.

```sh
flutter pub get
flutter test
flutter analyze
flutter run -d <ios-simulator-id>
```

Open `ios/Runner.xcworkspace` for Xcode signing and device builds. Generated iOS dependencies use Swift Package Manager. There are no backend credentials, paid services, or member-account setup required for this test build. `pubspec.lock` pins the tested dependencies.

## First test build

- Traditional Chinese default; Simplified Chinese interface option. Article text is never converted.
- Blog Posts, Videos, Saved, Settings; no Calendar, shared-folder Documents, or Bible tab.
- Live WordPress posts, paginated search, native article rendering, adjustable text, original-link sharing.
- Latest 20 articles initially saved offline; subsequent foreground synchronizations catch up every newly published article.
- Images and linked PDF/Office/text/EPUB materials stored with articles. Video bytes are never downloaded.
- Automatic saving enabled by default over cellular or Wi-Fi; manual mode available.
- 60-day download retention; oldest unprotected files evicted at the configurable 500 MB default budget. Protected items pause downloads if they fill the budget.
- Partial image/attachment failures explicitly labeled. Individual assets are limited to 100 MB and the remaining storage budget; failed/oversized attachments stay available through their original online links.
- Saved bookmarks are separate from Keep offline. Device-only persisted reading progress marks articles read after 60 seconds of active foreground viewing accumulated across visits. Mark unread resets it.
- Confirmed deleted posts remove protected copies too; network/auth failures never imply deletion. Edited cached posts are refreshed without alerts.
- Light/Dark/System appearance; approved five-solas icon installed in iOS and Android asset catalogs.
- In-app YouTube streaming with original controls and external-player fallback.

## Honest limits before public release

This is a local first-test implementation, not an uploaded TestFlight release.

- Notifications/backend are deliberately deferred to the second test build. The welcome screen requests no notification permission; Settings explains availability. Complete scheduling decisions are in `../docs/PRODUCT_SPEC.md`.
- Sync/download work runs while the app is active. No guaranteed closed-app daily refresh or background execution is claimed. Retry interrupted downloads by refreshing or selecting Download again.
- YouTube discovery is a test adapter for the channel's public **Videos** page (current `lockupViewModel` and older `videoRenderer` layouts). It excludes live badges/replay labels and does not use Shorts/Streams tabs or an all-uploads playlist. It does not use internal APIs or download streams. YouTube HTML is not an API contract: the adapter fails visibly when the layout changes. It loads the page's latest regular uploads; video search is explicitly limited to those loaded titles. Older videos remain available through the full-channel link. A supported production feed/API and stronger classification/archive coverage remain a public-release gate.
- YouTube embeds can show provider ads, consent dialogs, or restrictions; the app itself has no ad system.
- The cache resumes its persisted download queue after interruption and does not implement automatic cloud backup/sync, and uninstalling removes personal state. A device-level OS backup may still include app data according to the user's OS settings.
- App identity uses provisional bundle ID `org.reformedpiety.reformedPiety`. Apple team/signing, App Store Connect record, privacy/support URLs, real-device testing, and archive review remain required before TestFlight distribution.

## Structure

`lib/core/models.dart`: content metadata and storage policy.
`lib/core/content_service.dart`: WordPress API and YouTube test adapter.
`lib/core/app_store.dart`: state persistence, offline downloads, reconciliation, bookmarks.
`lib/core/reading_clock.dart`: monotonic active-reading time accounting.
`lib/ui/`: adaptive navigation, native article reader, embedded video, settings.
`test/`: unit/widget tests with controlled network responses.
`integration_test/live_smoke_test.dart`: opt-in live WordPress/YouTube simulator smoke test.

```sh
flutter test integration_test/live_smoke_test.dart -d <ios-simulator-id>
```

Full agreed specification: `../docs/PRODUCT_SPEC.md`.

## Verification record

- 12 unit/widget tests passed (controlled network and temporary disk fixtures).
- Live iPad integration smoke test passed: real WordPress list and article, bookmarking, current regular-video discovery, YouTube IFrame readiness and muted playback starting inside the app, and Settings navigation.
- iOS simulator build and unsigned iOS Release device build succeeded. The Release app is not signed or uploaded to App Store Connect.
- Physical-device battery/background/performance/accessibility checks and TestFlight distribution remain outstanding.
