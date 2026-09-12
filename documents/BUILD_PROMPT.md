# Build prompt — FlickrDownloader (native macOS port of FDownloadr)

Paste this whole file as the opening prompt of a fresh Claude Code session with
working directory `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`.

---

## What you are building

A native Swift / SwiftUI macOS app that bulk-downloads photos from Flickr.

It is a **ground-up redesign**, not a transliteration. The reference
implementation is a working PyQt6 app at
`/Users/tsevis/AI/ClaudeCode/FDownloadr`. Read it for *behaviour and hard-won
domain knowledge* — its module docstrings record real defects and why the
current shape exists — but do not copy its widget structure or its dark
hand-rolled stylesheet. The Mac app follows the macOS HIG and uses system
materials, so it looks correct in both Light and Dark mode and on any accent
colour.

Read these files in the reference app before writing code. They are small and
each one encodes a decision you would otherwise have to rediscover:

| File | Why it matters |
|---|---|
| `fdownloadr/api.py` | Flickr returns `stat=fail` code 201 on ~1 call in 3 during a blip. Retry policy: 4 attempts, backoff 0.5/1.5/3.0s. Transient codes `{105,106,111,112,201}`. |
| `fdownloadr/filenames.py` | Collision-free, traversal-safe, byte-budgeted filenames. Port the *rules*, exactly. |
| `fdownloadr/download_core.py` | `.part` temp file + atomic rename; `O_NOFOLLOW`; per-photo failure isolation. |
| `fdownloadr/search_filters.py` | Licence 0 is a real selection, not "unset". Size buckets are derived from which URL variants exist. |
| `fdownloadr/group_search.py` | Pool listing and in-group search are two different API methods with different filter support. |
| `fdownloadr/constants.py` | Flickr licence ids. Getting these wrong has legal consequences for the user. |
| `main.py` `DownloadSizeDialog.SIZE_OPTIONS` | The 11 download sizes and their pixel labels. |

---

## Non-negotiable correctness requirements

The Python app was adversarially tested and six real bugs were found and fixed.
**The Swift app must not reintroduce any of them.** Each needs a test.

1. **Per-section selection and pagination.** Selection, current page, total
   pages and per-page all belong to *one section*. A single shared store caused
   the Download button to download another section's photos, or nothing at all,
   while ticked thumbnails sat on screen. Model this as one
   `SectionState` value per section; there is no global "current page".

2. **A new query resets to page 1.** Searching a new term, loading a different
   user, or loading a different group all start at page 1. Only Next/Prev and
   the per-page control preserve position.

3. **OAuth signing is RFC 5849, not form encoding.** Percent-encode per RFC
   3986 — space is `%20`, never `+`; unreserved set is exactly
   `A-Za-z0-9-._~`. Sort parameters by **encoded** key. Verified against live
   Flickr: a `+` returns HTTP 401 `oauth_problem=signature_invalid`.

4. **Sort is exclusive and only offers values Flickr accepts.** Valid `sort`
   values for `flickr.photos.search`: `relevance`, `date-posted-asc|desc`,
   `date-taken-asc|desc`, `interestingness-asc|desc`. There is **no size or
   licence sort**. Critically, **Flickr answers `stat=ok` for a sort value it
   does not recognise** — it silently ignores it — so a wrong value is
   invisible in the response. Assert on the *outgoing query*, never on
   response status.

5. **Decode defensively.** Any malformed payload must surface as a user-facing
   error, never crash. Use `Codable` with a failable container so a `photos`
   that is a list instead of an object, a `pages` that is a string, or a null
   photo entry degrades to an error message. Page counts clamp to `max(1, …)`.

6. **Deterministic teardown.** Cancelling mid-batch must leave no partial file
   on disk and must report `Saved N of M`. Closing the window mid-download must
   cancel, await, and not lose the user's report.

---

## Product surface

Four sections, in a `NavigationSplitView` sidebar:

- **You** — the signed-in user's photostream. Requires login.
  `flickr.people.getPhotos` with `user_id=me`, signed.
- **Search** — keyword search across Flickr. `flickr.photos.search`.
- **User** — another user's public photos. Accepts a full URL
  (`https://www.flickr.com/photos/<name>/`) or a bare username/NSID; resolve a
  non-numeric identifier via `flickr.people.findByUsername`.
- **Groups** — a group's pool, plus search *within* the pool. Resolve a slug to
  an NSID via `flickr.urls.lookupGroup`, then `flickr.groups.getInfo`, then
  `flickr.groups.search` **requiring an exact name match** — taking the first
  fuzzy hit loads an unrelated group. Browsing the pool uses
  `flickr.groups.pools.getPhotos` (no filter support); searching inside it uses
  `flickr.photos.search` with `group_id` (full filter support). Say so in the
  UI when filters are inactive.

**Filters** (an inspector panel, not a modal): licence (multi-select, 17
values), size bucket (Any / S ≤500px / M 501–1024 / L ≥1025), sort (exclusive,
three values), colour (multi-select, 7 Flickr colour codes + Any).

**Download**: multi-select in the grid, choose one of 11 sizes, pick a
destination, batch download on a background actor with live progress and
working cancel.

---

## Architecture

```
FlickrDownloader/
├── Package.swift              # SPM, or project.yml if XcodeGen matches the
│                              # convention used by the reference Mac apps
├── Sources/
│   ├── FlickrKit/             # Pure Swift, zero AppKit/SwiftUI. Fully testable.
│   │   ├── FlickrClient.swift        # REST + retry policy
│   │   ├── OAuth1.swift              # RFC 5849 signing
│   │   ├── Models.swift              # Codable, defensive
│   │   ├── Filenames.swift           # port of filenames.py rules
│   │   ├── DownloadEngine.swift      # actor; .part + atomic rename
│   │   ├── SearchFilters.swift
│   │   └── GroupResolver.swift
│   └── FlickrDownloader/      # The app
│       ├── App.swift
│       ├── Splash/
│       ├── Sections/          # one view + one model per section
│       ├── Grid/              # PhotoGrid, PhotoTile, selection
│       ├── Filters/
│       └── Design/            # Theme, Typography, Colors
└── Tests/
    ├── FlickrKitTests/        # the bulk — no network, no UI
    └── FlickrDownloaderTests/
```

**Rules.** `FlickrKit` must not import SwiftUI or AppKit — that is what makes
it testable. Prefer `struct` and `let`; model state as value types and return
new values rather than mutating in place. Files stay 200–400 lines, 800 max.
Type annotations on every signature. No hardcoded secrets, ever.

**Concurrency.** Swift concurrency throughout — `async/await`, an `actor` for
the download engine, `@MainActor` on view models. No completion handlers, no
DispatchQueue.

---

## Authentication

Use `ASWebAuthenticationSession` with a custom callback URL scheme — **no
verifier-code copy-paste**. The Python app uses `oob` only because Qt made the
native flow awkward.

- Register a callback URL on the Flickr app record and document the exact value
  in the README.
- Store the API key/secret **and** the access token + token secret in the
  **Keychain**. Never in a `.env`, never in `UserDefaults`, never in source.
- On first launch, if no API key is present, show a clear onboarding sheet
  linking to `https://www.flickr.com/services/apps/create/`.
- Validate credentials are present before any signed call; fail fast with a
  message that says what to do.
- Log out must clear the Keychain entries and the You section's state.

---

## UI specification

Target "perfect", not "adequate". Concretely:

- **Window**: `NavigationSplitView`, unified toolbar, resizable, sensible
  minimum size, restores frame across launches.
- **Grid**: `LazyVGrid` with adaptive columns. Thumbnails load concurrently and
  cancel when scrolled away or when a newer page supersedes them — carry over
  the reference app's *generation token* idea so a stale page never draws into
  the current grid.
- **Selection**: native multi-select — click, ⌘-click, ⇧-click range, ⌘A,
  marquee drag. A selection count in the toolbar. Not per-tile checkboxes.
- **States**: every section needs a designed empty state, loading state, error
  state and no-results state. "Flickr is busy" (transient) reads differently
  from a real error.
- **Pagination**: page control in the bottom bar. Note that Flickr caps results
  at ~4000 regardless of the `pages` it reports — clamp the reachable page count
  and say why, rather than paging into duplicate results.
- **Accessibility**: full keyboard navigation, VoiceOver labels on tiles,
  Dynamic Type respected, contrast verified in both appearances.
- **Polish**: hover states, a real focus ring, drag a selection out to Finder,
  Quick Look on space bar, `⌘,` for settings, proper menu bar with an About
  item, progress in the Dock icon during a download.

---

## Testing

Swift Testing (`import Testing`) unless the reference Mac apps use XCTest — match
them. TDD: write the failing test, run it, confirm it fails, then implement.

- **80%+ coverage minimum**, concentrated in `FlickrKit`.
- Tests must be **offline and headless by default**. No test may open a window.
  If a test needs real UI, mark it so it is excluded from a plain `swift test`,
  mirroring the `gui` marker convention in the reference app.
- Port these specific cases from `FDownloadr/tests/` — they encode real
  defects: filename traversal/length/duplicate/non-ASCII handling, the retry
  policy, licence 0, size bucketing, exact group-name matching, cancel leaving
  no `.part`, and the six correctness requirements above.
- A separate, explicitly-opted-in live-API check (the equivalent of
  `test_flickr.py`).

---

## Build, sign, ship

- Use the shared script `/Users/tsevis/AI/ClaudeCode/sign-and-notarize.sh`.
  It signs with `Developer ID Application: CHARALAMPOS TSEVIS (TN899J6HRF)`,
  notarizes via the `crewlistr-notary` profile, and produces a stapled DMG.
  Do **not** pass `--python`; this is a native bundle.
- Provide `Info.plist` with a real bundle id, version, and
  `NSHumanReadableCopyright`. Hardened runtime on. Entitlements: outgoing
  network client, user-selected file read/write. Nothing else.
- A `Makefile` or `build.sh` with `build`, `test`, `run`, `sign` targets.

---

## Process

1. **Do not start coding.** First read the reference app's package modules and
   the three reference Mac apps listed in the splash section below, then write
   a short plan to `documents/PLAN.md` and stop for review.
2. Build `FlickrKit` first, TDD, fully tested, before any UI exists.
3. Then the splash screen and app shell.
4. Then one section at a time, Search first (it needs no auth).
5. Run a code review pass after each section.
6. Conventional commits (`feat:`, `fix:`, `test:`…). No attribution lines.

**Never launch the app to "verify" a change unless explicitly asked.** Never
let a test open a window on the desktop.

---

## Splash screen — follow the house pattern exactly

Every Tsevis Mac app opens with the same splash/about window. FlickrDownloader
must match it. **Read the canonical implementation before writing yours:**

- **Canonical:** `/Users/tsevis/AI/ClaudeCode/HipparchusMac/App/HipparchusApp/AboutView.swift`
  — 301 lines, the cleanest version, and its comments explain *why* each choice
  was made. Copy its structure.
- **Variant:** `/Users/tsevis/AI/ClaudeCode/nino/Sources/NinoUI/AboutView.swift`
  — same layout; measures logo height from the PNG's actual inked area rather
  than the artboard, which is worth stealing if the logo has uneven margins.
- **Same design in another toolkit:** `/Users/tsevis/AI/ClaudeCode/philon/src/Splash.tsx`
  — useful for the intended *look* if you want a second reference.
- **Design tokens:** `/Users/tsevis/AI/ClaudeCode/crewlisterpromac/Sources/CrewListrProMac/UI/Design/Theme.swift`
  — the dynamic light/dark colour pattern to adopt.

### Window mechanics (verbatim from the canonical source)

A plain `NSWindow`, **not** a SwiftUI `Window` scene. The reason is in the
source comment: it must be summonable from the application menu *and* shown
once at launch, and a `Window` scene leaves a stale entry in the Window menu.

```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
    styleMask: [.titled, .closable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
window.isMovableByWindowBackground = true
window.isReleasedWhenClosed = false
window.delegate = self
window.contentView = NSHostingView(
    rootView: AboutView(close: { [weak self] in self?.window?.close() })
)
window.center()
window.makeKeyAndOrderFront(nil)
```

> **Gotcha, verified:** that `560×620` `contentRect` is vestigial. The root view
> carries `.frame(width: 640, height: 580)`, and `NSHostingView` sizes the
> window to it, so the real window is **640×580**. Use 640×580 and don't
> propagate the stale number.

- No resize, no minimize (`.titled, .closable` only). No animation — it appears
  instantly at full opacity.
- Reusable: a second `show()` calls `makeKeyAndOrderFront(nil)` then `center()`.
- Dismissal goes through `NSWindowDelegate.windowWillClose`, so the Continue
  button and the close box mean the same thing and any continuation runs once:

```swift
func windowWillClose(_ notification: Notification) {
    let next = onDismiss
    onDismiss = nil
    next?()
}
```

- Shown at launch behind `UserDefaults` key **`"ShowAboutOnLaunch"`** (exact
  string). **Absent means yes** — first launch is when the credits are worth
  reading. A checkbox in the footer sets it false. Gate opening the main window
  on the splash closing, via the `showOnLaunchIfWanted(then:)` pattern.

### Layout and content

```swift
VStack(spacing: 0) {
    keyArt                  // 640×250 full-bleed banner + gradient scrim + lockup
    body(of: Self.about)
    Spacer(minLength: 0)
    footer                  // "show on launch" toggle, links, Continue
}
.frame(width: 640, height: 580)
.background(Color(nsColor: .windowBackgroundColor))
```

- **Key art**: 640×250, full-bleed, with a `LinearGradient` scrim from
  `black.opacity(0.0)` → `black.opacity(0.30)` so the lockup stays legible.
  Hipparchus renders its own map; Nino uses `documents/ninosplash.png`. For
  FlickrDownloader, produce a banner from a photo grid / contact-sheet motif and
  put it in `Assets.xcassets`.
- **Lockup on the key art**: logo + app name + tagline, aligned on a
  `.lastTextBaseline` guide with the logo height derived from `NSFont` metrics
  rather than an eyeballed offset:
  ```swift
  let titleCapInset = title.ascender - title.capHeight
  let titleLine = title.ascender - title.descender
  let subtitleBaseline = titleLine + subtitle.ascender
  return subtitleBaseline - titleCapInset
  ```

### Typography and spacing (house scale)

| Element | Spec |
|---|---|
| App name | `.system(size: 36, weight: .semibold)`, tracking `-0.6`, white, shadow `black.opacity(0.35)` r6 y1 |
| Tagline | `.system(size: 13, weight: .regular)`, `.opacity(0.85)` |
| Version / metadata | `.system(size: 11, weight: .medium)`, `.monospacedDigit()`, `.opacity(0.7)` |
| Body | `12.5pt`, `lineSpacing 2.0` |
| Footer legal | `10.5pt`, `lineSpacing 1.5` |
| Horizontal margin | `26pt` |
| Lockup bottom inset | `20pt` |
| Body top | `20pt` |

### Text

- Version from the bundle, never hardcoded:
  ```swift
  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  ```
- Attribution line, exact wording used across the house apps:
  **`Created by Charis Tsevis, with the help of Claude Code.`**
- Link to `tsevis.com` → `https://tsevis.com`.
- Write a real tagline for this app in the house voice — short, concrete, no
  marketing adjectives. Hipparchus uses *"Maps built from sources that stack"*.
- Body copy should say what the app does and name Flickr as the source, plus a
  line that photos remain the property of their owners and their licence terms
  apply — this app downloads other people's work, so that belongs on the splash.

### Design tokens

Adopt the dynamic-colour pattern so colours track appearance changes at runtime
without rebuilding the `Color`:

```swift
private static func dynamic(light: Int, dark: Int) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
    })
}
```

Derive the accent from the FlickrDownloader app icon, as CrewListr derives
`#0E6AFD` from its own. Do **not** reuse Flickr's pink/blue brand colours as the
app's accent — this is not an official Flickr client and must not imply it is.

### Toolchain — match the house apps (verified)

- **Swift 6.0**, **deployment target macOS 15.0**.
- **XcodeGen** (`xcodegen generate --spec App/project.yml`) as used by Nino, or
  SPM as used by CrewListr. Prefer XcodeGen: it keeps the app shell generated
  and the libraries in `Sources/`, which matches the `FlickrKit` split above.
- **Swift Testing** (`import Testing`), as Nino uses. Not XCTest.
- Team `TN899J6HRF`, Developer ID manual signing, hardened runtime on.
