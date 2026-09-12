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

    public static func run(credentials: OAuth1.Credentials,
                           anchor: ASPresentationAnchor) async throws -> OAuthFlow.Account {
        let temporary = try await requestToken(credentials: credentials)
        let callback = try await authorize(token: temporary.token, anchor: anchor)
        let verifier = try OAuthFlow.verifier(from: callback, expecting: temporary.token)
        return try await accessToken(credentials: credentials,
                                     temporary: temporary, verifier: verifier)
    }

    private static func requestToken(
        credentials: OAuth1.Credentials
    ) async throws -> OAuthFlow.TemporaryToken {
        let url = try OAuthFlow.requestTokenURL(credentials: credentials)
        return try OAuthFlow.temporaryToken(from: try await body(of: url))
    }

    private static func accessToken(credentials: OAuth1.Credentials,
                                    temporary: OAuthFlow.TemporaryToken,
                                    verifier: String) async throws -> OAuthFlow.Account {
        let url = try OAuthFlow.accessTokenURL(credentials: credentials,
                                               temporary: temporary, verifier: verifier)
        return try OAuthFlow.account(from: try await body(of: url))
    }

    /// These two endpoints answer form-encoded text, not JSON.
    private static func body(of url: URL) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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

    private static func authorize(token: String,
                                  anchor: ASPresentationAnchor) async throws -> URL {
        let url = try OAuthFlow.authorizationURL(token: token)
        let presenter = Presenter(anchor: anchor)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: OAuthFlow.callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: FlickrError.invalidInput("Sign-in was cancelled."))
                } else {
                    continuation.resume(throwing: FlickrError.transport(
                        error?.localizedDescription ?? "The sign-in window closed unexpectedly."))
                }
                // Held until the callback fires; released after it.
                _ = presenter
            }
            session.presentationContextProvider = presenter
            // A fresh session every time: reusing the browser's Flickr cookie
            // would sign in whoever last used this Mac's browser, silently.
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
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
