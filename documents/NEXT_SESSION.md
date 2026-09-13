# Caterina (formerly FlickrDownloader) — continuation prompt

Paste everything below as the opening message of a fresh Claude Code session
with working directory `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`.

---

You are continuing work on **FlickrDownloader**, a native Swift/SwiftUI macOS
app that bulk-downloads photos from Flickr. It is built, tested, signed,
notarised and installed in `/Applications`. Your job is to finish the parts
that could not be verified, not to rebuild what works.

Working directory: `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`
Reference implementation (PyQt6, read-only): `/Users/tsevis/AI/ClaudeCode/FDownloadr`

## Caterina — the direction since 2026-09-13

The app is now **Caterina**: download, upload, organize and browse a Flickr
library. The plan is `documents/CATERINA_PLAN.html`; the user accepted it and
all five of its recommended decisions (new bundle id, delete behind its own
permission, GRDB in its own module, no background stats helper, Photos import
and video in Phase 5). The user has Flickr **Pro**, so the stats API is usable.

**Phase 0 done:** renamed (bundle `com.tsevis.Caterina`, scheme
`caterina://auth`, Keychain service `com.tsevis.Caterina`, `CaterinaUI`), and
four tabs in the toolbar on ⌘1–⌘4 with Download as the first. The user is
registering a new API key named Caterina with that callback URL.

**Deviation from the plan:** the per-tab modules (`UploadFeature` etc.) are not
split out yet. Download's files lean on `AppModel` and would need `public` on
everything for no gain today; split each tab into its module when it gets code.

**Phase 1, mostly done (2026-09-13), offline-tested:**

* Signed POST writes (`FlickrWrite`, `FlickrClient.perform`), signature checked
  against oauthlib. A lost connection is retried only for a repeatable write.
* `FlickrPermission` read < write < delete, stored with the token; a Keychain
  document without it reads as `read`. Code 99 becomes `permissionNeeded`.
* `CallBudget`: sliding hour, tiered headroom, batch spacing 1 call/s.
* `CaterinaLibrary` module (GRDB 7.11.1): `LibraryStore`, `LibrarySync` (full,
  then changes, full weekly; never removes on a partial or suspicious pass).
* `PhotoEdit` → `PhotoChange` → writes from the difference; undo is the
  reverse. `EditBatch` + `BatchRunner` record, resume and undo batches.
* Organize shows the library copy's count and last sync, syncs at launch.
* A background review's MEDIUM/LOW findings are fixed (`3ed27fc`).

**Phase 2, the uploader (2026-09-13), offline-tested:**

* `UploadRequest`: multipart body written to a temp file, photo excluded
  from the signature (oauthlib vector), streamed by a 4-hour upload session.
  `FlickrClient.upload` never retries a lost connection; `checkTickets`.
* `FileMetadata`: IPTC title/caption/keywords, EXIF date, GPS via ImageIO.
* Albums: `albums(page:)`, `createAlbum` (never repeated), `addToAlbum`.
* `UploadRunner` + migration v3: queue on disk with security-scoped
  bookmarks, 2 at a time, tickets polled, album filing. Mid-send at quit →
  `interrupted`, resent only by the person.
* Upload tab: drop/⌘O, editable titles and tags, presets (Public, Friends &
  family, Private, plus the person's own), album choice, progress, Send
  Again. `PermissionRequestSheet` asks Flickr for write when first needed.
  Unfinished batches restore at launch.

**Phase 4, Browse & Insights (2026-09-14), offline-tested.** The user
verified uploads work and asked for the browser next, so Phase 3 (Organize UI)
was skipped for now; its engine (`PhotoEdit`, `BatchRunner`) exists.

* FlickrKit reads: `photoInfo`, `favorites` (50/page), `comments`,
  `contexts`, `exif` (hidden → `.hidden`), and Pro stats: `StatsDay` (GMT),
  `popularPhotos` (100/page), `totalViews`, `photoStats`,
  `referringDomains`, `referrers`. Shapes follow Flickr's documented XML
  mapped to JSON; **not yet checked live**.
* Migration v4: `photoDay`, `accountDay`. `StatsSnapshot` saves every whole
  day Flickr still holds, oldest first, one transaction per day; runs at
  launch. `topPhotos`, `risingPhotos`.
* Browse tab: rankings, account views chart, photo record with Swift Charts
  (views per day, faves over time), albums/groups, tags, camera, comments,
  faved by. Charts reviewed by eye from offscreen renders.
* Referrer data is read by FlickrKit but not shown yet; Explore and other
  people's photos in Browse are not built.

**Browse overhaul (2026-09-14), at the user's request, offline-tested and
reviewed (`4ee5308`):**

* Scopes (`BrowseScope`): your photos (all, timeline, tags, places, people,
  videos), rankings, albums/collections/galleries/groups, audience, licence,
  your faves, Explore. Layouts: list, grid, timeline, map (MapKit, 2,000 pins).
* FlickrKit `PhotoList` and structures: `groups(of:)`, `galleries()`,
  `collections()`, `contacts(page:)`, `photoList(_:page:)`.
* Migrations v5 (`mediumURL`, forces one full sync) and v6 (`FansIndex`:
  faves per photo, read in the background after each sync).
* Not possible via the API at account scale: people tagged in photos
  (per-photo only), cameras (per-photo EXIF), editing collections.
* `galleries.getList` paging by `page` with `continuation=0` is unverified live.

**Not in Phase 2 yet:** licence and group steps after upload, duplicate
detection, watch folders, Photos import, video limits (Phase 5), thumbnails
in the draft table, editing custom presets in the UI (store exists).

**Not done in Phase 1:** multipart upload body (moved to the start of Phase 2);
the permission-approval sheet and Activity panel (built with the first UI that
writes, Phase 3); a live write test — it needs a write token in the
environment, which the user must supply, and must touch only a test album.

**Unverified against the real API:** the `people.getPhotos` extras as decoded,
and `recentlyUpdated` paging. The user's sync in the running app is the check.

**SwiftPM trap seen today:** after changing a protocol in FlickrKit,
`swift test` ran stale CaterinaUITests binaries and reported green. Run
`swift build --build-tests` after protocol changes.

## Read these first

1. `README.md` — what it does, how to build, and the rules that are not obvious.
2. `documents/PLAN.md` — the original plan and the decisions it left open.
3. `documents/BUILD_PROMPT.md` — the original specification. Still the contract.

## Where it stands

24 commits, ~5,700 lines of source and ~4,600 of tests. **342 offline tests**
(`swift test`: offline, headless, opens no window) and **14 live tests** against
the real Flickr API, opt-in:

```bash
FLICKR_API_KEY=… FLICKR_API_SECRET=… swift test --filter Live
```

```
Sources/FlickrKit/            pure Swift; no SwiftUI, no AppKit. `make lint` fails if one appears.
Sources/FlickrDownloaderUI/   the SwiftUI layer, the splash and its artwork
App/                          thin Xcode shell (XcodeGen): Info.plist, entitlements, @main
Scripts/                      make-icon.py, make-keyart.py — both regenerate their output
```

`make test` · `make app` · `make sign` (Developer ID, notarised, stapled DMG) ·
`make lint` · `make coverage`.

## What is verified, and how

* All of FlickrKit, by unit test, plus live checks covering: a search with a
  space and an ampersand (the case that returns 401 when the encoder is wrong),
  licence filtering, both group-resolution paths, paging, and a full
  search → select → download with real JPEGs landing on disk.
* The licence table is checked against `flickr.photos.licenses.getInfo` and
  fails if Flickr and this build disagree on a single id or name.
* The splash, the four source states, the tile and the pagination bar, by
  rendering them offscreen with `ImageRenderer` and looking at the pixels.
* Palette contrast, resolved under both real appearances against WCAG.
* The window, sidebar, inspector and splash, by launching the app and
  screenshotting it.
* **By driving the running window with synthetic events** (see the note on
  Accessibility below): typing a query and searching, the splash's Continue
  button, click-to-select, the marquee sweep, arrow-key navigation, and space
  for Quick Look.

## What is NOT verified — this is the work

Items 1–3 below were open in the previous session and are now closed. What is
left is 4–7, and each needs a running window and a hand on the machine.

**Closed, for the record:**

1. **Sign-in.** ~~Crashed twice, never retried.~~ Resolved by evidence rather
   than by repeating the flow. Both crash reports
   (`~/Library/Logs/DiagnosticReports/FlickrDownloader-2026-09-12-0723*.ips`
   and `-0733*.ips`) are `dispatch_assert_queue` failures inside the
   `ASWebAuthenticationSession` handler, and both **predate** the fix in
   `f330552` (07:37); the installed bundle was built at 08:36. The app runs
   signed in as `tsevis`. No post-fix crash exists. A fresh sign-in round-trip
   still has not been performed — it needs the user's Flickr credentials, so
   do not attempt it yourself.
2. **Marquee drag.** Verified, and it was broken. A sweep begun *between* the
   tiles always worked; a sweep begun in the empty band *below* the last row
   did nothing, because the sweep surface is a `Color.clear` in a `ZStack` that
   sized itself to the tiles. Fixed in `6723c00`, with a test that measures the
   scroll content's height against the viewport.
3. **Arrow-key navigation and space for Quick Look.** Both verified by driving
   the window. Right-arrow twice moved the selection from tile 1 to tile 3 and
   the badge stayed at 1; space opened the Quick Look panel on the right photo.

**Still open:**

4. **Dragging a photo to the Finder** — it should land as a JPEG, not a
   `.webloc`. The provider is safe *by construction*: `PhotoDrag.provider`
   registers a file representation and no URL representation, so the Finder has
   nothing to make a shortcut from, and `PhotoDragRepresentationTests` now fails
   if a URL is ever registered beside it (`2373581`). But no file has actually
   been dropped. That is the only part left.
5. **The download sheet** — folder picker, progress bar, Cancel. The engine and
   the model are proven live; the sheet itself has never opened.
6. **A remembered download folder surviving a relaunch** (security-scoped
   bookmark).
7. **Ticking a filter checkbox** — the search should re-run once, not per tick.
   The model-level behaviour is already covered by
   `AppModelTests.changingAFilterRerunsTheQueryFromPageOne`; what is unproven is
   only the checkbox-to-model plumbing.

**Found by reading the code and a sandboxed probe (2026-09-13), fixed, not yet
seen in a running window:**

* **6 was broken.** The sheet called `isWritableFile` before any security scope
  was started, and under the sandbox that answers `false` for an ungranted
  folder (confirmed with an ad-hoc-signed sandboxed probe). Every remembered
  folder would have been refused after a relaunch. `DownloadFolder.isWritable`
  now checks inside the scope. A stale bookmark (folder renamed) was also
  discarded; it is now followed and refreshed. No
  `files.bookmarks.app-scope` entitlement is needed — the probe created and
  resolved security-scoped bookmarks without it.
* **7 had a bug beside the one asked about.** The `Form` was `.disabled` for
  photostreams and pools and Size tried `.disabled(false)`, which cannot undo a
  parent's; Size was greyed out everywhere but search. Now gated per section
  by `FilterAvailability`. The re-run-once plumbing reads correct: one binding
  set per tick, debounced 500ms in `AppModel.setFilters`.
* **4:** dragging from a multi-selection drags one photo — `.onDrag` carries a
  single provider. The comment claimed otherwise; corrected. Multi-item drag
  would need macOS 26's `dragContainer`; not done.
* **5:** the sheet's error message now clears when a new folder is chosen.

The *logic* behind 4–7 is extracted and tested (`GridSelection`, `Marquee`,
`PhotoDrag.promisedName`, `DownloadFolder`). What is untested is the gesture
plumbing.

**Performance work (2026-09-13), offline-tested; the transport also checked
against the real CDN via the public feed (byte-identical JPEGs, 404 throws):**

* **Download transport streams URLSession's own chunks** (`ChunkTransport.swift`,
  a delegate routing per task). The old per-byte `AsyncBytes` loop measured
  32 MB/s with a core pegged; the new one 1,657 MB/s on the same 64MB file.
  The old one also held back anything under 64KB, so a stalled server
  delivered nothing until the timeout.
* **Four photos transfer at once** (`DownloadEngine.simultaneousTransfers`).
  The report keeps selection order. Cancelling keeps every photo already
  finished — no longer only those *before* the one in flight; two tests that
  encoded the one-at-a-time contract were updated to say so.
* **Thumbnails decode inside the store's actor** (`ShouldCacheImmediately`),
  not on the main thread at first draw.
* Checked and left alone: `@Observable` already skips equal writes (Swift
  6.2), so no-op selection sweeps cost nothing.

## Hard constraints — read before acting

* **Never run XCUITest.** A UI-test target was tried; its runner needs its own
  authentication and running it destabilised the host application. The target
  was removed. Do not add one back.
* **Claude Code *can* drive the interface, as of 2026-09-12.** The user granted
  Accessibility to **Terminal.app** — the responsible process, not the `claude`
  binary — and synthetic `CGEvent`s and AppleScript UI scripting both work.
  Confirm it still holds before relying on it, and be careful how you test:
  * Post a move and read the cursor back *within ~30ms*. Sampling after a long
    sleep reads whatever the user's own hand did in the meantime, which looks
    exactly like a dropped event and is how a previous session wrongly
    concluded the permission was missing.
  * `osascript -e 'tell application "System Events" to return name of first
    process whose frontmost is true'` succeeds **without** Accessibility —
    process listing is ungated, so it proves nothing. Ask for a real UI query
    and look for `-25211`.
  * `CGWarpMouseCursorPosition` is also ungated. It moving the cursor proves
    nothing either.
  * TCC is read at process launch, so a grant made while Terminal is running
    may need Terminal restarted — which ends the session.
* **`screencapture` will not run while a mouse button is held.** To see a drag
  in flight, capture in-process with `Quartz.CGWindowListCreateImage`.
* **Re-check what is frontmost before every click.** Opening a Finder window
  buried the app mid-task, and the drags that followed went into an unrelated
  window. `screencapture -l<id>` captures an occluded window fine and will not
  warn you; `CGWindowListCreateImage` captures whatever is actually on top, so
  use it to confirm the app is really there.
* **Do not drive the interface while the user is using the machine.** Synthetic
  events go wherever focus is at that instant. Ask for a hands-off window first,
  and stop if the app's state changes in a way you did not cause.
* **Do not type an API key into any field, or write one to the Keychain.** Ask
  the user to do it. The key lives only in the Keychain and in the environment
  variables used by the live tests.
* **No test may open a window.** `swift test` must stay silent. Offscreen
  rendering with `ImageRenderer` is the sanctioned way to look at a view.
* **Do not launch the app to "verify" a change** unless the user asks.

## Things that were got wrong once — do not regress them

Each of these has a test that fails if it comes back.

* **A cancelled `AsyncThrowingStream` ends, it does not throw.** The chunk loop
  exits normally with a half-written file, so cancellation is re-checked *after*
  the loop, before the atomic rename.
* **A size fallback downgrades, never upgrades.** The requested size is a
  ceiling.
* **A photo must not decide how big its tile is.** As a `ZStack` child a
  `.scaledToFill()` image reports the size it wants to fill at and the stack
  grows to match. `PhotoTileLayout` exists for this.
* **A `ZStack` is only as tall as its tallest child — so an invisible surface
  in one covers only what its siblings cover.** The marquee's `Color.clear` sat
  behind the tiles and stopped where they stopped, leaving the empty band below
  the last row belonging to the `ScrollView`. The scroll content takes the
  viewport height as a *floor*; a fixed height would truncate any page taller
  than the window instead, and that case is pinned too.
* **`.fullSizeContentView` does not mean SwiftUI ignores the title bar.** The
  content view spans the frame but `contentLayoutRect` does not;
  `hosting.safeAreaRegions = []` is what makes the splash full-bleed.
* **`ASWebAuthenticationSession` calls its handler on a background queue.** A
  main-actor-isolated handler traps in `dispatch_assert_queue`. The handler is
  `@Sendable` so the compiler refuses any capture that would isolate it again.
* **One Keychain item, read once.** Six items meant six unlock prompts; reading
  from a view body meant one per redraw.
* **Sort is exclusive and only offers values Flickr accepts.** Flickr answers
  `stat=ok` for a sort it does not recognise, so assert on the outgoing query,
  never on the response.
* **Selection and pagination belong to one source.** No global current page.
* **A new query resets to page 1**; only paging preserves position, and changing
  page size preserves the *position*, not the page number.
* **Licence 0 is a selection, not "unset"**, and `noKnownRestrictions` is not
  permission — it is an institution saying it has not found a rights holder.
* **The drag provider promises a file and never a URL.** Registering a URL
  beside it is a one-line convenience, and the Finder then prefers it and writes
  a `.webloc` instead of a photograph.
* **Every write of untrusted bytes goes through `SafeFile`** (`O_NOFOLLOW`, and
  `O_EXCL` for names that should be new).
* **Fixed sleeps in tests are forbidden.** Poll a condition; eight tests once
  failed together purely because the machine was busy.
* **`Quick Look_<id>.jpg` is the intended name, not a bug.** `AppModel` passes
  `title: "Quick Look"` deliberately, and `TemporaryFiles.prefixes` depends on
  that exact prefix to sweep the file afterwards.

## Deliberately not done — pick up only if asked

* **Custom-scheme squatting.** macOS has no ownership model for URL schemes;
  any app can register `flickrdownloader://`. The real fix is a Universal Link
  on a domain with an `apple-app-site-association` file, which needs a domain.
  Documented in the README with what limits the damage today.
* **Secrets are ordinary Swift strings**, not zeroed on deallocation. Only
  reachable by an attacker who already has code execution as the user.
* **Dock progress is a badge** ("12/40"), not a drawn bar — at 128 points a bar
  is illegible.

## Start by

Asking the user to exercise items 4–7 above, or — with their agreement and a
hands-off machine — driving the window yourself under the rules in **Hard
constraints**. Report what breaks, then fix it the way the rest of this codebase
was fixed: a test that fails against the old behaviour first.
