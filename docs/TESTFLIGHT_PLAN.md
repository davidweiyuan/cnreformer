# First TestFlight build — release gates

## Implemented baseline

Flutter app with the agreed branding, articles, streaming videos, native offline reading, downloadable materials, saved bookmarks, 60-second active reading progress, script/theme/font preferences, and storage policy. The previous SwiftUI project is retained for reference, not the active product direction.

## Validation before inviting members

1. Run unit/widget tests and static analysis.
2. Run the live simulator smoke test against WordPress and YouTube.
3. On a physical iPhone and iPad: verify YouTube playback, rotation/fullscreen, document previews, original-link sharing, connectivity loss, airplane-mode reading after force-quit, low-storage behavior, and protected download recovery.
4. Confirm all interface copy in both Chinese scripts; check large system text and VoiceOver.
5. Review network and cache failure messages, deletion/update behavior, and background lifecycle reading time.
6. Confirm the latest regular-video list excludes Shorts/live/replays for the real channel. Plan supported production discovery before a public release.

## Apple configuration still needed

- Choose the owner's signing Team and final bundle ID in Xcode.
- Create/select the App Store Connect app record for Reformed Piety.
- Supply owner-approved support and privacy-policy URLs and contact details.
- Review App Privacy answers including third-party WordPress and YouTube networking/storage.
- Review export-compliance and content-rights answers; do not auto-submit legal attestations.
- Archive a signed Release build, validate it, then show the archive and metadata for approval before upload.
- Internal TestFlight testing first; external church-member testing may require Apple's beta review.

## Phase two

Notifications with free-hosting-first design, anonymous device preferences, per-time-zone digests, one-hour late-content grouping, quiet hours, and deduplication. Do not deploy a paid service or upgrade without the owner's approval.
