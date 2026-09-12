import AuthenticationServices
import Foundation
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// What the browser hands back, and what it means.
///
/// **Deliberately not `@MainActor`.** `ASWebAuthenticationSession` calls its
/// completion handler on a background queue; a handler that touches main-actor
/// state from there traps in `dispatch_assert_queue` under Swift 6 and takes
/// the process with it. That happened twice, on the callback returning from
/// Flickr — at the exact moment sign-in would otherwise have succeeded. This
/// suite runs off the main actor, so a mapping that needed it would not compile.
@Suite struct SignInCallbackTests {

    @Test func aCallbackURLIsTheAnswer() throws {
        let url = URL(string: "flickrdownloader://auth?oauth_token=a&oauth_verifier=b")!
        let result = FlickrSignIn.outcome(callback: url, error: nil)
        #expect(try result.get() == url)
    }

    @Test func closingTheWindowIsACancellationNotAFailure() {
        let cancelled = NSError(domain: ASWebAuthenticationSessionErrorDomain,
                                code: ASWebAuthenticationSessionError.canceledLogin.rawValue)
        let result = FlickrSignIn.outcome(callback: nil, error: cancelled)

        guard case let .failure(error) = result,
              let flickr = error as? FlickrError else {
            Issue.record("expected a FlickrError")
            return
        }
        #expect(flickr.message.lowercased().contains("cancelled"))
        // Not transient: retrying on the user's behalf would reopen a window
        // they just closed.
        #expect(!flickr.isTransient)
    }

    @Test func anythingElseIsReportedWithWhatTheSystemSaid() {
        let boom = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                           userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        let result = FlickrSignIn.outcome(callback: nil, error: boom)

        guard case let .failure(error) = result,
              let flickr = error as? FlickrError else {
            Issue.record("expected a FlickrError")
            return
        }
        #expect(flickr.message.contains("offline"))
        #expect(flickr.isTransient)
    }

    @Test func neitherAURLNorAnErrorStillSaysSomething() {
        let result = FlickrSignIn.outcome(callback: nil, error: nil)
        guard case let .failure(error) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(!(error as? FlickrError).map(\.message).isNilOrEmpty)
    }

    /// The mapping must work from an arbitrary queue, because that is where it
    /// is called from.
    @Test func itWorksFromABackgroundQueue() async throws {
        let url = URL(string: "flickrdownloader://auth?oauth_verifier=x")!
        let answered: URL = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = FlickrSignIn.outcome(callback: url, error: nil)
                continuation.resume(returning: (try? result.get()) ?? URL(fileURLWithPath: "/"))
            }
        }
        #expect(answered == url)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
