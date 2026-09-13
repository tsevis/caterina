# Caterina — build the Organize tab (Phase 3)

Paste everything below the line as the opening message of a fresh Claude Code
session with working directory `/Users/tsevis/AI/ClaudeCode/FlickrDownloader`.

---

You are continuing **Caterina** (formerly FlickrDownloader), a native Swift 6.2 /
SwiftUI macOS app for managing a Flickr account, named for Flickr co-founder
Caterina Fake. Download, Upload and Browse are built, reviewed, notarised and in
daily use by the owner, who is a **Flickr Pro** user. Your job is the fourth tab,
**Organize**: Flickr's web Organizr, rebuilt as batch edits with undo.

## Read these first, in this order

1. `documents/CATERINA_PLAN.html`: the accepted plan. Read the **Organize**
   section, **What Flickr's API won't allow**, and **Phases → 3**.
2. `documents/NEXT_SESSION.md`: the handover. Its **Hard constraints** and
   **Things that were got wrong once** sections are binding.
3. `README.md`: build, sign and the rules that are not obvious.

## Where things stand (2026-09-14)

64 commits on `master`, **600 offline tests** (`swift test`, headless, opens no
window). Install is `make sign`, then
`ditto .build/xcode/Build/Products/Release/signed/Caterina.app /Applications/Caterina.app`.
Do not sign or install without saying so first; it uploads to Apple's notary.

```
Sources/FlickrKit/        Flickr, pure Swift. No SwiftUI/AppKit (make lint enforces).
Sources/CaterinaLibrary/  The local copy of the library in SQLite (GRDB 7.11.1).
Sources/CaterinaUI/       SwiftUI. One folder per tab: Download, Upload, Browse; Shell.
App/Caterina/             Thin XcodeGen shell: Info.plist, entitlements, @main.
```

The Organize tab today is `PlannedTabView` plus `LibraryStatusBar`
(`RootView.content`, case `.organize`). `AppTab.isBuilt` is false for it.

## The engine already exists. Build on it; do not rebuild it

* **`PhotoEdit`** (`FlickrKit/Library/PhotoEdit.swift`): a pure transform of a
  `LibraryPhoto`. Its cases are `setTitle`, `appendToTitle`, `setDescription`,
  `addTags`, `removeTags`, `setVisibility`, `setLicense`,
  `shiftTaken(seconds:)`, `setLocation` and `removeLocation`.
* **`PhotoChange`** (`PhotoChange.swift`): works out the Flickr writes from the
  difference between the photo before and after: `setMeta`, `setTags`,
  `setPerms`, `setDates`, `licenses.setLicense` and
  `geo.setLocation`/`removeLocation`. **Undo is `reversed`**: nothing
  remembers what an edit meant, only the before and the after.
* **`FlickrWrite`**: carries `repeatable`, meaning safe to retry after a lost
  connection, and `permission`, which is `.write` or `.delete`.
  `FlickrClient.perform(_:priority:)` refuses a write the token does not allow
  and maps Flickr code 99 to `.permissionNeeded`. It never retries a
  non-repeatable write after a lost connection.
* **Edit batches** (`CaterinaLibrary/LibraryStore+Edits.swift`, migration v2):
  * `createBatch(title:edit:photos:)` stores every photo's before and after,
    and leaves out photos the edit would not change.
  * `undoBatch(for:)` writes back only what was actually applied, last photo
    first.
  * The read side is `entries(in:)`, `summary(of:)` and `recentBatches(limit:)`.
* **`BatchRunner`** (`BatchRunner.swift`): records each photo before starting
  the next.
  * A photo Flickr refuses is marked failed and the batch carries on.
  * `permissionNeeded`, a transient error or cancellation stops the batch with
    the rest still pending, so it can be resumed.
  * After each photo it updates the local copy.
* **`CallBudget`**: shared by the whole app.
  * Calls at `.edit` priority are spaced one per second and stop at 3,000 an
    hour, leaving headroom for what the person is looking at.
  * `CallBudget.standard.estimatedDuration(calls:priority:)` gives the
    up-front cost, e.g. "800 calls, about 14 minutes".
* **`PermissionRequestSheet`** (`CaterinaUI/Auth`): explains why, opens
  Flickr's approval page for exactly the level needed, then runs a
  continuation. The Upload tab shows how to use it (`UploadStatusBar`).
  **Deleting needs `.delete`**, which Flickr grants separately.
* **The library copy** (`LibraryStore.photos(_:order:limit:offset:)`) has
  these filters: `.all`, `.untagged`, `.withoutLocation`, `.withLocation`,
  `.tagged`, `.matching`, `.takenIn`, `.licensed`, `.seenBy(Audience)` and
  `.videos`. It also offers `tagCounts()`, `monthCounts()` and
  `photos(ids:)`.
* **Reusable from Browse**:
  * `PhotoTiles`/`BrowseTile` (a grid with a size slider), `FlowLayout`,
    `RowThumbnail` and `TagsIndex`.
  * `AccountDirectory`: albums, collections, galleries, groups and contacts,
    loaded once.
  * The scope and generation pattern in `BrowseModel`.
* **Albums in FlickrKit today**: `albums(page:)`, `createAlbum` (never
  repeated) and `addToAlbum` (treats "already in set" as done), plus
  `photoList(.album(id:ownerID:), page:)`.

## What to build

These are the plan's Organize features, as the person uses them.

1. **Finding photos.** A left panel of smart views from the library copy:
   * not in an album, untagged, no location, with location, recently updated,
     videos;
   * each audience, each licence;
   * a month-by-month timeline and a tag list.

   "Not in an album" has no local data. Use `flickr.photos.getNotInSet`, or
   build album membership from `photosets.getPhotos`.
2. **The batch tray.** Select in a grid (marquee and ⌘/⇧ clicks: see
   `GridSelection` and `Marquee` in FlickrKit and Download). Photos go into a
   tray that persists across views. The tray shows how many photos and what
   the chosen edit will cost in calls and time, **before** it runs.
3. **Edits** on the tray:
   * **Titles and descriptions**: set, or append, with patterns like
     `{date} · {n}`.
   * **Tags**: add, remove, replace, and rename one tag across the whole
     library.
   * **Who can see and do what**: visibility, plus who can comment and who can
     add tags (`setPerms` `perm_comment`/`perm_addmeta`, optional).
   * **Safety level and content type**: `setSafetyLevel`, `setContentType`.
   * **Hidden from search**, **licence**, **date taken**: set, or shift by a
     time-zone error.
   * **Location**: on a MapKit map; set or remove it, and who can see it
     (`geo.setPerms`).
   * **Rotate**: `photos.transform.rotate`.
   * **People**: `photos.people.add`/`delete`.
4. **Albums**:
   * create, rename and describe, delete;
   * add the tray, remove photos;
   * set the cover (`setPrimaryPhoto`);
   * drag to reorder photos in an album (`reorderPhotos`) and the albums
     themselves (`orderSets`).
5. **Groups**:
   * send the tray to several groups, and remove photos from pools;
   * read each group's throttle first (`groups.getInfo`) and report
     rejections per group.
6. **Galleries**: add photos (`galleries.addPhoto`). Galleries hold *other*
   people's photos, so this starts from Browse.
7. **Collections**: read-only. The API cannot edit them; say so and link to
   flickr.com.
8. **Undo and the Activity panel**:
   * Recent batches, each with progress, failures with Flickr's reason, and
     Resume or **Undo**.
   * **Delete is the exception.** It is not undoable, needs `.delete`, has its
     own confirmation that names the count, and is never part of a preset or a
     multi-edit.

**Done when:** everything the owner does in flickr.com's Organizr can be done
here, and every change except deletion can be undone here.

## Traps to design around. Decide them with tests, not by hope

* **Tags lose their spelling.** The library copy holds Flickr's *clean* tags
  ("newyork"). `setTags` with that list would overwrite the photographer's raw
  tags ("New York"). Before a tag edit, read the raw tags (`photos.getInfo`
  gives `raw`), or store raw tags in the library copy. Losing someone's tag
  spelling across 800 photos is a real regression.
* **A stale "before".** A batch computes its after from the local copy. A photo
  edited on flickr.com since the last sync would have that edit silently
  overwritten. Refresh before creating a batch: an incremental `LibrarySync`,
  or `photos.getInfo` per photo at run time with a check that the before still
  matches.
* **No batch methods exist.** 800 photos means 800 calls or more. Show the cost
  first, run at `.edit` priority, and keep the window usable while it runs.
* **Non-repeatable writes.** `photosets.create`, `comments.addComment` and
  `galleries.addPhoto` must never be retried after a lost connection. Mark each
  new `FlickrWrite` correctly, and test it.
* **Async lists.** Any list that loads asynchronously needs a generation token.
  Comparing scopes by value let a stale reply land twice.
* **Per-item errors are not run-stopping errors.** One refused photo must not
  stop a batch or an index, but Flickr being unreachable must.
* **`photos.delete`** needs `perms=delete`. Treat the approval as a separate,
  explicit moment.

## How to work

Follow `~/.claude/CLAUDE.md`, which is binding:

* **Research first.** Check Flickr's documentation for every new method with
  WebFetch (`https://www.flickr.com/services/api/<method>.html`). Record
  arguments, required or optional, and error codes before writing code.
* **TDD.** Write the test, run it and see it fail, implement, then see it pass.
  Match the existing test style: fakes like `ScriptedTransport`, and
  expectations generated independently where possible. OAuth vectors came from
  `oauthlib`, which is installed.
* **Small files.** 200–400 lines, functions under 50 lines, immutable values.
  Extend `FlickrClient` in feature files (`FlickrClient+Albums.swift` shows the
  pattern).
* **Review in chunks.** After each meaningful chunk, run a background
  code-review agent over the commits. Fix CRITICAL, HIGH and MEDIUM, and LOW
  where cheap. Each earlier review found real bugs.
* **Commits.** Conventional messages that explain *why*.
* **Stale SwiftPM tests.** After changing a protocol or an initializer, run
  `swift build --build-tests` (or touch the test files). SwiftPM has run stale
  test binaries and reported green.
* **Look at charts and layouts once.** Render them offscreen with
  `ImageRenderer`, and read the PNG.
* **Updates.** Keep the owner updated in plain words. They reply briefly and
  test in the real app.

## Hard constraints: repeated here because they matter

* **No window in tests.** No test may open a window. Never run XCUITest. Do
  not launch the app to verify unless the owner asks.
* **Keys.** Never type an API key into a field or write one to the Keychain.
  If the owner pastes one into chat, say that it is now in the transcript.
* **Live write tests.** Only against a **dedicated private test album**, with a
  write token the owner supplies in the environment. **Never** edit, re-licence
  or delete the owner's existing photos from a test.
* **Driving the interface.** Do not drive it while the owner is using the
  machine. Ask for a hands-off window first.

Start by reading the three documents. Then propose, in a short message, the
order you will build the eight parts in and how you will handle the raw-tags
and stale-before traps. Then begin.
