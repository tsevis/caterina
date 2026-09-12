# FlickrDownloader — continuation prompt

Paste everything below as the opening message of a fresh Claude Code session
with working directory `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`.

---

You are continuing work on **FlickrDownloader**, a native Swift/SwiftUI macOS
app that bulk-downloads photos from Flickr. It is built, tested, signed,
notarised and installed in `/Applications`. Your job is to finish the parts
that could not be verified, not to rebuild what works.

Working directory: `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`
Reference implementation (PyQt6, read-only): `/Users/tsevis/AI/ClaudeCode/FDownloadr`

## Read these first

1. `README.md` — what it does, how to build, and the rules that are not obvious.
2. `documents/PLAN.md` — the original plan and the decisions it left open.
3. `documents/BUILD_PROMPT.md` — the original specification. Still the contract.

## Where it stands

18 commits, ~5,700 lines of source and ~4,600 of tests. **339 offline tests**
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

## What is NOT verified — this is the work

Nobody has performed these. They need a running window and a hand:

1. **Sign-in.** It crashed twice, was fixed, and has not been retried. The
   whole **You** source depends on it. The callback `flickrdownloader://auth`
   is registered with Flickr and demonstrably redirects back to the app.
2. **Marquee drag** in the grid. Rewritten twice; never dragged.
3. **Arrow-key navigation** and **space for Quick Look**.
4. **Dragging a photo to the Finder** — it should land as a JPEG, not a
   `.webloc`.
5. **The download sheet** — folder picker, progress bar, Cancel. The engine and
   the model are proven live; the sheet itself has never opened.
6. **A remembered download folder surviving a relaunch** (security-scoped
   bookmark).
7. **Ticking a filter checkbox** — the search should re-run once, not per tick.

The *logic* behind 2–7 is extracted and tested (`GridSelection`, `Marquee`,
`PhotoDrag.promisedName`, `DownloadFolder`). What is untested is the gesture
plumbing.

## Hard constraints — read before acting

* **Never run XCUITest.** A UI-test target was tried; its runner needs its own
  authentication and running it destabilised the host application. The target
  was removed. Do not add one back.
* **Claude Code has no Accessibility permission on this Mac.** AppleScript UI
  scripting returns `-25211`, and synthetic `CGEvent`s are posted but not
  delivered (verified by moving the cursor and reading the position back). You
  can launch the app and screenshot its windows; you cannot click or type in it.
  To capture a window without grabbing the user's other work, get its id from
  `CGWindowListCopyWindowInfo` (pyobjc `Quartz` is available) and use
  `screencapture -l<id>`.
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
* **Every write of untrusted bytes goes through `SafeFile`** (`O_NOFOLLOW`, and
  `O_EXCL` for names that should be new).
* **Fixed sleeps in tests are forbidden.** Poll a condition; eight tests once
  failed together purely because the machine was busy.

## Deliberately not done — pick up only if asked

* **Custom-scheme squatting.** macOS has no ownership model for URL schemes;
  any app can register `flickrdownloader://`. The real fix is a Universal Link
  on a domain with an `apple-app-site-association` file, which needs a domain.
  Documented in the README with what limits the damage today.
* **Secrets are ordinary Swift strings**, not zeroed on deallocation. Only
  reachable by an attacker who already has code execution as the user.
* **Dock progress is a badge** ("12/40"), not a drawn bar — at 128 points a bar
  is illegible.

## House conventions

* Conventional commits; **no attribution lines**.
* The splash follows `HipparchusMac/App/HipparchusApp/AboutView.swift` exactly —
  plain `NSWindow`, 640×580, dismissal through `windowWillClose`. The Tsevis
  mark sits in the lockup, lower-left of the key art, sized from font metrics
  and corrected for the PDF's own margin.
* Signing uses `../sign-and-notarize.sh`, which this project extended with
  `--entitlements FILE`. **That flag is not optional here** — `codesign --force`
  without it re-signs with no entitlements, and this app is sandboxed. The
  script verifies they survived.
* `swift build`/`swift test` work without Xcode; `make app` needs XcodeGen.

## Start by

Asking the user to exercise items 1–7 above, or — if they have granted
Accessibility to Claude Code since — verifying whether synthetic events are
actually delivered before assuming you can drive the interface. Report what
breaks, then fix it the way the rest of this codebase was fixed: a test that
fails against the old behaviour first.
