import Foundation

/// The four tabs across the top of the window.
///
/// **One library underneath all four.** They share the sign-in, the model and
/// the selection; a tab is a way of working on the library, not a separate
/// document.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case download, upload, organize, browse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .download: "Download"
        case .upload: "Upload"
        case .organize: "Organize"
        case .browse: "Browse"
        }
    }

    public var systemImage: String {
        switch self {
        case .download: "arrow.down.circle"
        case .upload: "arrow.up.circle"
        case .organize: "square.grid.3x3.square"
        case .browse: "chart.line.uptrend.xyaxis"
        }
    }

    /// ⌘ plus this key. Left to right, as every tabbed Mac window numbers them.
    public var shortcut: Character {
        switch self {
        case .download: "1"
        case .upload: "2"
        case .organize: "3"
        case .browse: "4"
        }
    }

    /// One sentence, in the words of the person using it.
    public var purpose: String {
        switch self {
        case .download:
            "Search Flickr, a photostream or a group, and save what you select."
        case .upload:
            "Send photos to Flickr with their titles, tags, albums and licence already set."
        case .organize:
            "Edit many photos at once: albums, tags, who can see them, licences and places."
        case .browse:
            "See every number Flickr keeps for a photo: views, faves, comments and where they came from."
        }
    }

    /// Whether the tab does its job yet. An unbuilt one says what is coming
    /// instead of showing an empty grid that looks broken.
    public var isBuilt: Bool { self != .organize }
}
