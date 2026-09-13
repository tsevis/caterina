import Foundation

/// One call that changes something on Flickr.
///
/// **`repeatable` is the question a retry has to ask.** Setting a title twice
/// leaves one title; creating an album or adding a comment twice leaves two.
/// When the connection drops mid-call nobody knows whether Flickr acted, so
/// only a repeatable write is sent again.
public struct FlickrWrite: Sendable, Equatable {
    public let method: String
    public let arguments: [String: String]
    public let repeatable: Bool
    /// `write` for nearly everything; `delete` for deleting a photo.
    public let permission: FlickrPermission

    public init(method: String, arguments: [String: String], repeatable: Bool,
                permission: FlickrPermission = .write) {
        self.method = method
        self.arguments = arguments
        self.repeatable = repeatable
        self.permission = permission
    }

    /// In name order, so the same write always signs the same way.
    var parameters: [OAuthParameter] {
        [OAuthParameter(name: "method", value: method)]
            + arguments.keys.sorted().map { OAuthParameter(name: $0, value: arguments[$0] ?? "") }
            + [OAuthParameter(name: "format", value: "json"),
               OAuthParameter(name: "nojsoncallback", value: "1")]
    }
}
