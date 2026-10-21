# cnreformer for iPhone and iPad

Native SwiftUI app for iOS/iPadOS 17+, with four tabs:

- **Calendar**: monthly calendar with dated document entries that open the reader. Dates come from catalog metadata or Cornerstone-style filenames.
- **Documents**: searchable document list with language filtering.
- **Library**: links to posts from davidweiyuan.wordpress.com, with search and older-post pagination.
- **Bible**: English LSB and Chinese FHL web readers.

Documents open in a PDFKit / Quick Look reader from Documents or Calendar.

Sources stay read-only. The app remembers the connection and document index, recursively lists a selected provider folder, and caches documents when opened. Refresh Folder updates the index; Reload from Source in the reader updates a cached document. Previously opened documents remain readable offline. Switching folders replaces the visible index but retains the private cache. Search covers titles and supplied categories/languages, not document contents.

## Run

Open `CNReformer.xcodeproj`, select the CNReformer scheme, choose an iPhone or iPad simulator, and Run. For a physical device, choose your Apple Development team in Signing & Capabilities. Xcode 16+ is required. There are no third-party dependencies.

```sh
xcodebuild -project CNReformer.xcodeproj -scheme CNReformer -sdk iphonesimulator -derivedDataPath /tmp/cnreformer-build CODE_SIGNING_ALLOWED=NO build
swift test
```

## OneDrive through Files

1. Install OneDrive on the iPhone/iPad and sign in.
2. Enable OneDrive under Files → Browse → Edit. Make the intended shared folder accessible in OneDrive.
3. In cnreformer, open Shared Folder → Choose Shared Folder and select it.
4. Refresh the folder to discover additions/removals, then open a document.

The app uses Apple's folder picker with `asCopy: false`, security-scoped bookmarks, and coordinated reads. Folder selection and availability of shared folders depend on the installed provider and account; some providers do not expose selectable folders. No Microsoft app registration is needed for this mode. A real-device OneDrive check is still required.

## HTTPS web folder

Publish documents plus a `cnreformer.json` catalog on an HTTPS server, then paste the catalog URL into Shared Folder → Web folder. See `Examples/cnreformer.json`. Relative document paths resolve against the catalog URL; absolute HTTPS URLs are also supported. Each entry requires a unique `id`, `title`, and `url`; optional `date`, `language`, and `category` populate the calendar and filters.

Generate a catalog for an existing folder:

```sh
python3 Tools/make_catalog.py /path/to/published-folder
```

Host that folder at an HTTPS URL. This script only creates the index; it does not upload or publish anything. Refresh/regenerate the catalog when its content changes. Prefer PDF exports of Keynote/PowerPoint decks for consistent slide rendering. Quick Look previews presentation files when supported by iOS; packaged `.key` directories should be exported to PDF first. Animations and desktop Keynote conversion are not implemented.

An ordinary OneDrive sharing URL is an HTML page, not a web catalog. Direct Microsoft sign-in / Graph sharing-link browsing is not implemented. Microsoft states that OneDrive for Business and SharePoint shared-item API access requires an authenticated user context. Use Files for those accounts, subject to provider support.

## Validation and scope

The simulator SDK build is checked for arm64 and x86_64. Core tests cover valid/invalid filename dates, relative URL resolution, duplicate IDs, unsupported catalog versions, and rejection of unsafe URLs/file types. The app has been launched in iPhone and iPad simulators. The Bible tab has been visually verified loading John 1 from the live LSB website on iPad. Physical-device OneDrive access requires testing with your account. App Store signing, icon artwork, Microsoft OAuth, Google Calendar, OCR, annotations, and slide assembly remain outside this first mobile version.

References: [Apple directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [Microsoft shared-item API](https://learn.microsoft.com/en-us/graph/api/shares-get?view=graph-rest-1.0).

## Bible reading

The **Bible / 聖經** tab provides two online readers:

- **English · LSB** opens the [Legacy Standard Bible reader](https://read.lsbible.org/).
- **中文 · 信望愛** opens the [FHL responsive Chinese Bible reader](https://bible.fhl.net/NNUI/_rwd/), linked from [bible.fhl.net](https://bible.fhl.net/index.html).

Use the language selector above the reader to switch. Each source retains its own web view, navigation history, and last-opened URL; the selected language is remembered across launches. The existing English saved location is preserved. The two passages are independent, not automatically synchronized. Use each site's passage search, book/chapter controls, translation options, and reading settings. No shared-folder connection is required.

The native toolbar provides Back, Forward, Bible Home, Reload, Share, and Open in Browser for the selected source. Bible reading requires internet access. Loading and website/network errors are shown with a retry action. Scripture is displayed directly from the publishers' websites with their attribution and controls intact, not bundled or downloaded as an offline Bible. Website preferences use the embedded browser's persistent website storage. External publisher links open in the system browser; older same-host HTTP links are upgraded to HTTPS. Website availability and features are controlled by the respective providers.

Validation: simulator SDK build and six core tests pass. English John 1 and the Chinese FHL reader have both been visually verified on the iPad Pro simulator. Source-policy tests cover independent saved locations, host restrictions, and HTTPS upgrades preserving passage query parameters and fragments.

## Blog Library

Library loads public posts from [朝聖之旅](https://davidweiyuan.wordpress.com/) using the WordPress.com posts API. It shows 25 posts at a time, newest first, with publication dates. Submit a search to search across the blog, load older posts for more results, and pull to refresh. Tap a post to open its original URL in an in-app Safari browser with Reader mode when available. Use Done to return to the list. Internet access is required; network errors offer a retry. No WordPress sign-in or shared-folder setup is needed.

Document browsing and shared-folder controls remain in Documents; dated documents remain available from Calendar. Library no longer shows document cards. Blog tests cover API response decoding, title entities, URL validation, and pagination/search query encoding.
