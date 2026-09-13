import AppKit
import AuthenticationServices
import Foundation

import FlickrKit

/// Signing in, in the browser, without a verifier to copy out of it.
///
/// The reference application used `oob` and made the user paste a nine-digit
/// code back into a dialog, because Qt made the callback awkward. A registered
/// callback scheme removes that step; what it adds is the obligation to check
/// what comes back through it, which `OAuthFlow.verifier(from:expecting:)` does.
@MainActor
public enum FlickrSignIn {

    /// Sign in, or sign in again to allow more: Flickr issues a new token
    /// either way, and it replaces the old one.
    public static func run(credentials: OAuth1.Credentials,
                           permission: FlickrPermission = .read,
                           anchor: ASPresentationAnchor) async throws -> OAuthFlow.Account {
        let temporary = try await requestToken(credentials: credentials)
        let callback = try await authorize(token: temporary.token, permission: permission,
                                           anchor: anchor)
        let verifier = try OAuthFlow.verifier(from: callback, expecting: temporary.token)
        return try await accessToken(credentials: credentials, temporary: temporary,
                                     verifier: verifier, permission: permission)
    }

    private static func requestToken(
        credentials: OAuth1.Credentials
    ) async throws -> OAuthFlow.TemporaryToken {
        let url = try OAuthFlow.requestTokenURL(credentials: credentials)
        return try OAuthFlow.temporaryToken(from: try await body(of: url))
    }

    private static func accessToken(credentials: OAuth1.Credentials,
                                    temporary: OAuthFlow.TemporaryToken,
                                    verifier: String,
                                    permission: FlickrPermission) async throws -> OAuthFlow.Account {
        let url = try OAuthFlow.accessTokenURL(credentials: credentials,
                                               temporary: temporary, verifier: verifier)
        return try OAuthFlow.account(from: try await body(of: url), permission: permission)
    }

    /// Every request carries a timeout, including these two.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    /// These two endpoints answer form-encoded text, not JSON.
    private static func body(of url: URL) async throws -> String {
        do {
            let (data, response) = try await session.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FlickrError.malformedResponse("Flickr's reply was not readable text.")
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // A 401 here is almost always the signature, and the signature
                // is almost always the API secret.
                throw FlickrError.invalidInput(
                    "Flickr refused the sign-in (HTTP \(http.statusCode)). "
                    + "Check the API key and secret in Settings.")
            }
            return text
        } catch let error as FlickrError {
            throw error
        } catch {
            throw FlickrError.transport(error.localizedDescription)
        }
    }

    private static func authorize(token: String, permission: FlickrPermission,
                                  anchor: ASPresentationAnchor) async throws -> URL {
        let url = try OAuthFlow.authorizationURL(token: token, permission: permission)
        let presenter = Presenter(anchor: anchor)
        let holder = SessionHolder()

        return try await withCheckedThrowingContinuation { continuation in
            // **This closure must not be main-actor isolated.**
            // `ASWebAuthenticationSession` calls it on a background queue, and
            // Swift 6 checks: a handler that touches main-actor state from
            // there traps in `dispatch_assert_queue` and takes the process with
            // it. That is not theoretical — it crashed twice, on the callback
            // coming back from Flickr, at the moment sign-in would have
            // succeeded.
            //
            // Marking it `@Sendable` is what keeps it that way: the compiler
            // now refuses any capture that would re-introduce the isolation,
            // so this cannot regress quietly. It resumes the continuation and
            // nothing else; everything main-actor happens on the far side of
            // the `await`.
            let handler: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                // Captured so the session and its presenter outlive this call;
                // never read, so no isolation is inherited.
                _ = holder

                continuation.resume(with: outcome(callback: callback, error: error))
            }

            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: OAuthFlow.callbackScheme,
                completionHandler: handler)
            session.presentationContextProvider = presenter
            // A fresh session every time: reusing the browser's Flickr cookie
            // would sign in whoever last used this Mac's browser, silently.
            session.prefersEphemeralWebBrowserSession = true
            holder.keep(session: session, presenter: presenter)
            session.start()
        }
    }

    /// What the browser's answer means.
    ///
    /// `nonisolated` and separate from the handler so it can be called — and
    /// tested — from whatever queue `AuthenticationServices` happens to use.
    nonisolated static func outcome(callback: URL?,
                                    error: (any Error)?) -> Result<URL, any Error> {
        if let callback { return .success(callback) }

        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            // Closing the window is a decision, not a failure.
            return .failure(FlickrError.invalidInput("Sign-in was cancelled."))
        }
        return .failure(FlickrError.transport(
            error?.localizedDescription ?? "The sign-in window closed unexpectedly."))
    }

    /// Tells the system which window the sheet belongs to.
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor
        init(anchor: ASPresentationAnchor) { self.anchor = anchor }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
}

/// Keeps the session and its presenter alive for the length of the flow.
///
/// **Declared outside `FlickrSignIn`, deliberately.** Nested inside a
/// `@MainActor` type it would be main-actor isolated, and the completion
/// handler that captures it would inherit that isolation — which is the crash
/// this file's comment describes. At file scope it is isolated to nothing.
private final class SessionHolder: @unchecked Sendable {
    private var session: ASWebAuthenticationSession?
    private var presenter: AnyObject?

    func keep(session: ASWebAuthenticationSession, presenter: AnyObject) {
        self.session = session
        self.presenter = presenter
    }
}
