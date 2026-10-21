# Reformed Piety · 歸正靈命塑造

Status: agreed first-release specification. Flutter replaces the original SwiftUI prototype; original sources remain available for reference. Owner: David Wei Yuan. Audience: fellow church members, primarily outside mainland China. This is a personal devotional ministry, not an official church publication.

## Delivery

- One Flutter codebase. Prioritize iPhone/iPad testing through TestFlight; Android follows later.
- First cohort: small group of church members, eventually including both platforms. Public App Store / Google Play release after testing.
- Free content, no app ads, subscriptions, donations, or member accounts. YouTube may independently display its own advertising.
- First build: articles, in-app streaming videos, offline articles/images/materials, bookmarks, settings. Second build: notification backend and scheduling.
- No paid infrastructure or paid upgrade without owner approval. Owner has Apple Developer membership; Google Play developer enrollment still needed.
- Owner will maintain the app with Flutter experience and AI assistance.

## Identity and navigation

- Name: Reformed Piety · 歸正靈命塑造. Simplified Chinese label: 归正灵命塑造.
- Approved icon: open Bible, five ivory rays/pages for the five solas, central gold cross. Navy, ivory, gold palette.
- Four tabs: Blog Posts (default), Videos, Saved, Settings.
- Remove Calendar and shared-folder Documents. Defer English/Chinese Bible readers.
- Traditional Chinese menus/buttons initially; member can select Simplified Chinese. Never convert article text.
- Follow device light/dark mode initially; manual Light / Dark / System setting.
- Adjustable article font size.

## Publishing

- WordPress: https://davidweiyuan.wordpress.com/ is the source of articles and attached sermon materials.
- Feature the newest post; do not label an old post as a freshly published daily devotional.
- YouTube: https://www.youtube.com/@davidweiyuan (channel UCaiCyyGDr0HGi6zrS561_vQ).
- Automatically discover regular uploaded videos; exclude Shorts, live streams, and replays. Videos play inside the app through the YouTube player; never download video bytes in release one.
- Keyword search for blog content and video titles. Clearly describe the scope when video search is limited to loaded uploads.
- Original WordPress/YouTube URLs used for sharing.
- Owner confirms redistribution and offline-storage permission for articles, images, and materials.

## Reading, saved state, and downloads

- Initial automatic download: latest 20 articles and their images/linked sermon materials. Download all new articles as the app synchronizes thereafter.
- Automatic downloads on by default, member may choose manual. Article/images/material downloads may use cellular or Wi-Fi.
- Videos are streaming only in release one (supersedes earlier optional video-download discussion).
- 60-day rolling offline retention; member can mark articles/materials Keep offline to exempt them. Retention is measured from successful initial download, so older manually chosen articles remain usable for 60 days.
- 500 MB automatic-download budget, configurable. Evict oldest unprotected download first. Protected items count toward the budget; when they fill it, pause downloads and explain how to free space/increase the limit. Never silently delete protected downloads to make room.
- Bookmarks are separate from offline protection and do not cause downloads. Saved includes articles and videos; offline reading remains available from downloaded articles.
- Reading time accumulates across visits. Mark read after 60 seconds of active foreground article viewing. Background time and time in another screen do not count. Mark unread resets elapsed reading time.
- Preferences, bookmarks, progress and downloads are device-local. No cross-device sync or recovery after uninstall.
- Edited posts update cached copies silently. Confirmed deleted posts remove local content including protected copies, bookmarks, and attached files after reconnecting. Absence from a feed or network/authorization failure is NOT proof of deletion.
- Offline status must distinguish complete downloads from partial/failed images or attachments. Downloading is best effort while the app can run; iOS does not promise immediate background execution while closed.

## Notification rules — second build

- Welcome flow allows skipping notification setup. Enable later through Settings.
- Anonymous backend stores push token, time zone, notification preferences; never bookmarks/reading history. No member account required.
- Daily digest at member-selected local time, containing both new articles and videos. Stay quiet if nothing is new.
- Extra alert enabled by default, with opt-out: first late item after daily digest starts a one-hour grouping window. At most one extra alert per local day. Later arrivals wait for next daily digest.
- Quiet hours default 22:00–08:00 local time, editable. Apply only to extra alerts, not explicitly chosen digest time.
- Hold extra alert until quiet hours end. If a digest covers its content first, cancel the held alert. Never notify twice about the same items.
- Implementation must test time-zone changes, daylight-saving gaps/overlaps, midnight windows, deduplication, stale tokens and denied permission.

## Acceptance and release gates

First test build must demonstrate real WordPress content, article reading, original-link sharing, regular-video discovery/player, offline restart, script/theme/size preferences, bookmark vs protection behavior, storage budget/retention, and 60-second foreground reading accumulation.

Before TestFlight upload: Apple signing/team, bundle identifier and App Store Connect record, privacy/support URLs, export compliance, licensed assets, real-device playback/background/offline checks, and owner approval of the concrete archive. No upload or publication is implied by producing an unsigned/simulator build.

YouTube discovery must be documented honestly: a test-build public-page adapter is fragile and not equivalent to an official API contract; a production supported discovery path must be validated before public launch. Do not classify every short-duration video as a Short. Keep all provider attribution and player controls intact.
