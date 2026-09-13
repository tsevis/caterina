# Caterina

A native macOS app that bulk-downloads photos from Flickr — search results, a
person's photostream, a group's pool, or your own account — at a size you pick,
into a folder you pick.

It is a ground-up redesign of [FDownloadr](../FDownloadr), a PyQt6 application,
in Swift and SwiftUI. The behaviour was ported; the interface was not.

## What you need before it works

Flickr gives every application its own API key. Getting one takes a minute and
costs nothing.

1. Create a key at <https://www.flickr.com/services/apps/create/>.
2. On the app's record at Flickr, set the **callback URL** to exactly:

   ```
   caterina://auth
   ```

   This is what lets sign-in hand the verifier straight back to the app instead
   of making you copy a nine-digit code out of a browser. The same value is
   registered in `App/Caterina/Info.plist` under `CFBundleURLTypes`.
3. Launch Caterina and paste the key and secret into the sheet it opens.

The key, the secret and the access token are kept in the macOS **Keychain**.
They are never written to a file, to `UserDefaults`, or into source.

Searching and browsing need only the key. Signing in is needed only for the
**You** section — your own photostream, including photos that are not public.
Sign-in asks Flickr for `read` permission and nothing else.

## Building

```bash
make test     # offline, headless: no network, no windows
make app      # Release .app in .build/xcode
make run
make sign     # Developer ID, notarised, stapled DMG
```

`swift build` and `swift test` work without Xcode. `make app` needs
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

Requires macOS 15 and Swift 6.

## How it is laid out

```
Sources/
  FlickrKit/            pure Swift — no SwiftUI, no AppKit, fully testable
  CaterinaUI/         the SwiftUI layer, and the splash's artwork
App/                    a thin Xcode shell: Info.plist, entitlements, @main
Tests/                  233 tests — the bulk in FlickrKit, none opening a window
```

`FlickrKit` links no UI framework, and `make lint` fails if one appears. That is
what lets every rule below be tested without a window on screen.

## The rules that are not obvious

Each of these was a defect in the reference application, and each has a test.

* **Selection and pagination belong to one source.** Four sources, four
  `SectionState` values, no global "current page". A load only ever writes back
  into the source it belongs to, and carries a generation so a superseded reply
  is dropped rather than drawn.
* **A new query starts at page 1.** A new term, a different user, a different
  group, a changed filter. Only Next/Previous and the per-page control preserve
  a position.
* **OAuth signing is RFC 5849, not form encoding.** Space is `%20`, never `+`;
  the unreserved set is exactly `A-Za-z0-9-._~`; parameters sort by their
  *encoded* key. A `+` where a `%20` belongs is answered with HTTP 401
  `oauth_problem=signature_invalid`, which looks like a credentials problem and
  is not one.
* **Sort is exclusive and offers only values Flickr accepts.** Flickr answers
  `stat=ok` for a sort value it does not recognise, so a wrong one is invisible
  in the reply. The tests assert on the outgoing query, never the response.
* **Filters are hidden where they do nothing.** `flickr.groups.pools.getPhotos`
  and `flickr.people.getPhotos` accept no licence, colour or sort parameter; the
  inspector says so rather than pretending.
* **Licence 0 is a selection, not "unset".** All Rights Reserved is a licence
  you can search for. Dropping it made that search return everything.
* **Size comes from the largest variant Flickr published.** Flickr never
  upscales, so a variant's existence is a lower bound. Asking whether a *small*
  variant exists classified every photo as small.
* **A group name must match exactly.** `flickr.groups.search` is fuzzy; taking
  its first result loaded unrelated groups.
* **A size fallback downgrades, never upgrades.** The size you pick is a
  ceiling. A photo with no file at that size is saved at the largest size below
  it — not at the Original, which on three hundred photos is gigabytes you did
  not ask for.
* **Downloads are atomic.** Bytes go to `<name>.part`, opened with `O_NOFOLLOW`
  so a planted symlink cannot redirect the write, and are renamed into place
  only once the transfer completes. Cancelling deletes the partial file and
  reports "Saved N of M", where N is the number of files actually on disk.
* **Flickr serves about 4000 results.** The reachable page count is clamped to
  that, with the reason shown, rather than letting you page into duplicates.

## What it writes, and what it keeps

* **A `Credits.csv` beside every download**, naming the photographer, the
  licence, a link to the terms, and the photo's page on Flickr. Creative Commons
  licences ask for attribution; a folder of JPEGs cannot give it.
* **Credentials in the Keychain**, as one item, marked *this device only* so
  they never ride an iCloud sync onto another Mac. Sign Out removes the token
  and keeps the API key.
* **A bounded thumbnail cache** in the app's container, and the folder you last
  downloaded into, as a security-scoped bookmark. Nothing else is stored, and
  nothing is sent anywhere but Flickr — there is no analytics, no telemetry and
  no crash reporting in this app.

## Known limitation: the sign-in callback

Sign-in returns through the custom URL scheme `caterina://auth`. macOS
has no ownership model for custom schemes — any app can register the same one,
and which app receives the redirect is not guaranteed. Two things limit what
that is worth to an attacker: the callback's request token is checked against
the one this window asked for, and the API key is yours rather than embedded in
the app, so an intercepted verifier cannot be exchanged without your secret. The
real fix is a Universal Link on a domain with an `apple-app-site-association`
file, which needs a domain; until then, this is the trade-off.

## Licence and credit

Photographs, titles and licence information come from the Flickr API and belong
to the photographers who made them. This is an independent application, not
affiliated with or endorsed by Flickr.

Created by Charis Tsevis, with the help of Claude Code.
