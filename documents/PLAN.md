# FlickrDownloader — implementation plan

Native macOS port of FDownloadr (PyQt6). Ground-up redesign; the Python app is
read for domain knowledge, not for structure.

Reference read before writing this: `fdownloadr/{api,filenames,download_core,
search_filters,group_search,constants,thumbnail_loader}.py`, `main.py`
(`DownloadSizeDialog.SIZE_OPTIONS`, OAuth signing, `_tab_state`, `color_map`),
`HipparchusMac/App/HipparchusApp/AboutView.swift`, `nino/Sources/NinoUI/
AboutView.swift`, `nino/App/project.yml`, `nino/Package.swift`,
`crewlisterpromac/.../Design/Theme.swift`.

Toolchain on this machine, verified: Swift 6.2.4 (Xcode 26.3), xcodegen at
`/opt/homebrew/bin/xcodegen`, no swiftlint. Deployment target macOS 15.0,
language mode 6, team TN899J6HRF.

## 1. Shape

Nino's split exactly, because it is the one that makes `swift test` work
without Xcode:

```
FlickrDownloader/
├── Package.swift              # FlickrKit — swift build / swift test, no Xcode
├── Sources/
│   ├── FlickrKit/             # pure Swift; no SwiftUI, no AppKit
│   └── FlickrDownloaderUI/    # SwiftUI; splash art in Resources/ (see below)
├── App/
│   ├── project.yml            # xcodegen generate --spec App/project.yml
│   └── FlickrDownloader/      # Info.plist, entitlements, Assets.xcassets, main
├── Tests/
│   ├── FlickrKitTests/        # the bulk — offline, headless
│   └── FlickrDownloaderUITests/
├── Makefile                   # build test run sign
└── documents/
```

Splash key art lives in `Sources/FlickrDownloaderUI/Resources`, not in the app
target — Nino records two bugs that hid in `App/`, which `swift test` cannot
see. `Bundle.module` resolves identically in the app and in a test;
`Bundle.main` would be the test runner and the picture would come back empty.

FlickrKit targets: one module, ~8 files, each 200–400 lines.
`FlickrClient`, `OAuth1`, `Models`, `Filenames`, `DownloadEngine`,
`SearchFilters`, `GroupResolver`, `Licenses` (+ `SortOrder`, `SizeBucket`).
Everything `struct`/`let`; `DownloadEngine` is the one `actor`; view models
are `@MainActor` classes. async/await throughout, no completion handlers.

## 2. The six non-negotiables, and how each is pinned

| # | Requirement | Design | Test |
|---|---|---|---|
| 1 | Per-section state | `struct SectionState { photos, selection, page, totalPages, perPage, query }`, one per `Section`. No global `currentPage`. Download reads the *active* section's state and asserts identity. | Load Search, select 3; load Groups; assert Search's selection and page survive and Download targets Search's photos. |
| 2 | New query resets to page 1 | `SectionState.applying(query:)` returns page 1 whenever the query's identity differs; only `nextPage`/`previousPage`/`perPage` preserve it. | Same term → page kept; different term/user/group → page 1. |
| 3 | RFC 5849 signing | Own percent-encoder: unreserved `A-Za-z0-9-._~` only, space → `%20`. `URLComponents`/`addingPercentEncoding(withAllowedCharacters:)` are *not* trusted; the allowed set is written out. Sort by encoded key, then encoded value. | Golden vectors from RFC 5849 §3.4.1.1 plus a case with space, `+`, `&`, `=` and non-ASCII; assert base string byte-for-byte. |
| 4 | Sort exclusive, valid values only | `enum SortOrder: String` with exactly `relevance`, `date-posted-asc/desc`, `date-taken-asc/desc`, `interestingness-asc/desc`. Non-optional on the request struct, so "unset" is unrepresentable. | Assert on the **outgoing query dictionary**, never on response `stat` — Flickr answers `stat=ok` for a sort it does not know. Exhaustive test over all cases. |
| 5 | Defensive decoding | `Codable` with a lenient container: `photos` as list or object, `pages`/`total` as `String` or `Int`, `null` entries dropped rather than fatal. Page counts `max(1, …)`. Failure → `FlickrError.malformedResponse(String)`. | Fixture corpus of malformed payloads; each must throw or degrade, none may crash. |
| 6 | Deterministic teardown | `DownloadEngine` actor; cancel via structured `Task` cancellation checked per chunk. `.part` removed on cancel/failure; atomic `rename` only on complete transfer. Result is `DownloadReport(saved: Int, attempted: Int, failures: [..])`. Window close `await`s the task and keeps the report. | Cancel mid-batch → no `.part` on disk, report says Saved N of M, N matches files present. |

## 3. Ported domain rules

- **Retry.** 4 attempts, backoff 0.5/1.5/3.0s, transient codes `{105,106,111,112,201}`. Transient exhausted reads as "Flickr is busy", not as an error. Injectable clock so tests do not sleep.
- **Filenames.** `filenames.py` rules verbatim: 200-byte basename budget, id appended always, id hashed (BLAKE2s-64 → `SHA256` truncated, or CryptoKit BLAKE-equivalent; hash choice does not matter, *hashing whenever sanitising changed the id* does), allowed extensions `.jpg/.jpeg/.png/.gif`, alnum + space/hyphen/underscore only, UTF-8-safe truncation.
- **Download.** `.part` + atomic rename, `O_NOFOLLOW` on the temp open, per-photo failure isolation, connect/read timeouts on every request.
- **Licences.** All 17 ids exactly as `constants.py`. Licence `0` is a selection, not "unset" — modelled as `Set<License>?` where `nil` means no filter and an empty set is impossible by construction.
- **Size buckets.** Derived from which URL variants exist (Flickr never upscales): `L` ← `url_o/k/h/l`, `M` ← `url_c/z/m`, `S` ← `url_n/s/t/sq`. Not a thumbnail-existence check.
- **Groups.** `urls.lookupGroup` → `groups.getInfo` → `groups.search` with **exact** name match (unescaped, spaceless, casefolded) or nothing. Pool = `groups.pools.getPhotos`, no filters; in-pool search = `photos.search` + `group_id`, full filters. The inspector says which is active.
- **Download sizes.** The 11 from `SIZE_OPTIONS`, default Large, with the largest-first fallback chain.
- **Thumbnails.** Generation token carried per request; a result whose generation is stale is dropped. `.task(id:)` on the tile gives cancel-on-scroll-away for free; the token covers in-flight work that outlives the view.
- **4000-result cap.** `reachablePages = min(reportedPages, ceil(4000 / perPage))`, with a one-line explanation in the pagination bar when it clamps.

## 4. Authentication

`ASWebAuthenticationSession` with a custom scheme. Keychain for api key/secret
and access token/secret — never UserDefaults, never `.env`, never source.
Onboarding sheet when no key, linking to the Flickr app-create page.
Credentials validated before any signed call. Log out clears Keychain and the
You section's state. README documents the exact callback URL to register.

## 5. Splash

House pattern, copied from the canonical Hipparchus implementation: plain
`NSWindow` (`.titled, .closable, .fullSizeContentView`, transparent titlebar,
hidden title, movable by background, `isReleasedWhenClosed = false`), root view
`.frame(width: 640, height: 580)` — the 560×620 contentRect is vestigial and is
not propagated. No resize, no minimize, no animation. `windowWillClose` is the
single dismissal path so Continue and the close box mean the same thing and the
continuation runs once. `ShowAboutOnLaunch`, absent means yes.

Layout, typography and spacing exactly as specified: 640×250 full-bleed banner
(contact-sheet motif), scrim `0.0 → 0.30`, lockup on `.lastTextBaseline` with
logo height measured from `NSFont` metrics, and Nino's inked-area correction if
the mark carries a margin. 36/13/11/12.5/10.5pt, 26pt margins, version from
`CFBundleShortVersionString`. Attribution line and tsevis.com link verbatim.

Body copy: what the app does, Flickr named as the source, and that photos
remain their owners' with their licence terms applying. Tagline drafted in the
house voice at implementation time.

## 6. Sequence

0. **This plan → review.** ← we are here
1. **FlickrKit, TDD, complete, before any UI.** Order: `OAuth1` → `Models` →
   `FlickrClient` + retry → `Filenames` → `SearchFilters` → `GroupResolver` →
   `DownloadEngine`. RED, confirm the failure, GREEN, refactor.
2. App shell + splash. Xcodegen spec, Info.plist, entitlements
   (`com.apple.security.network.client`, `files.user-selected.read-write`,
   nothing else), hardened runtime, Makefile.
3. Sections one at a time, **Search first** (needs no auth) → User → Groups →
   You. `code-reviewer` pass after each.
4. Signing: `sign-and-notarize.sh <app>` — no `--python`.

Tests: Swift Testing (`import Testing`), 80%+ concentrated in FlickrKit,
offline and headless. Nothing in a plain `swift test` may open a window;
window-requiring tests are tagged and excluded by default, mirroring the `gui`
marker convention. Live-API check is a separate, explicitly opted-in target.

Conventional commits, no attribution lines.

## 7. Questions raised at review, and what was decided

1. **Sort labels.** The Python UI offers three (Relevance / Date / Interesting
   → `relevance`, `date-posted-desc`, `interestingness-desc`) while Flickr
   accepts seven. The spec says "exclusive, 3". Proposal: keep the three house
   labels in the picker and model all seven in `SortOrder`, so the asc variants
   can be exposed later without a type change. **Decided: the three.** All seven are in `SortOrder`; the picker shows `SortOrder.offered`.
2. **Colour codes.** The reference offers 7 + Any (`0`–`6`); Flickr's palette
   has ten (white, grey, black are separate codes). **Decided: parity with the reference.**
3. **Callback URL.** The native OAuth flow needs a callback registered on the
   Flickr app record, which only you can do. Proposal:
   `flickrdownloader://auth`. **Registered in `Info.plist` and documented in the
   README; it still has to be set on the Flickr app record before the You
   section works.**
4. **Accent colour.** Derived from the app icon, per the CrewListr pattern —
   but there is no icon yet. **Decided: controls use the system accent**, so the window is correct under
   whatever accent the user has chosen; a small identity amber taken from the
   key art carries the few marks that are about the application itself. Sample
   the icon instead once there is one. Flickr's own blue/pink are not
   used as the accent, since this is not an official client.
5. **Bundle id.** **Decided: `com.tsevis.FlickrDownloader`, version `0.1.0`.**

## 8. What changed from this plan while building it

* `Section` was renamed `PhotoSource`: SwiftUI has a `Section`, and the
  collision was ambiguous at every use site.
* The splash gates what happens *after* launch rather than the main window
  itself — the canonical Hipparchus pattern, where `showOnLaunchIfWanted(then:)`
  is called from the root view's `.task` and its continuation does the
  post-launch work. Suppressing the window scene instead was fragile.
* Two review passes (security and code) ran after the sections were built
  rather than after each one; their findings are in the fourth commit.
