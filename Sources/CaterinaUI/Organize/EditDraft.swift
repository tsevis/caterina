import Foundation

import FlickrKit

/// The kinds of edit the tray offers. Deleting is not one of them: it cannot
/// be undone and has its own confirmation.
public enum EditKind: String, CaseIterable, Identifiable, Sendable {
    case title, description, tags, visibility, safety, licence, dateTaken, location

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .title: "Title"
        case .description: "Description"
        case .tags: "Tags"
        case .visibility: "Who Can See"
        case .safety: "Safety & Search"
        case .licence: "Licence"
        case .dateTaken: "Date Taken"
        case .location: "Location"
        }
    }
}

/// What the edit form holds, validated into edits.
///
/// Plain values, so the form can bind to it and a test can check it without
/// a window.
public struct EditDraft: Equatable, Sendable {
    public enum TextMode: String, CaseIterable, Sendable { case set, append }
    public enum TagMode: String, CaseIterable, Sendable { case add, remove, replace, rename }
    public enum DateMode: String, CaseIterable, Sendable { case shift, set }
    public enum LocationMode: String, CaseIterable, Sendable { case set, remove, privacy }
    public enum SafetyField: String, CaseIterable, Sendable { case safety, contentType, hidden }

    public var kind: EditKind

    public var textMode = TextMode.set
    public var text = ""
    /// Replacing with nothing clears every title or description: asked for
    /// in so many words, never by an empty field.
    public var clearsText = false

    public var tagMode = TagMode.add
    /// Comma-separated, so one tag can hold spaces.
    public var tagText = ""
    public var renameFrom = ""
    public var renameTo = ""

    public var isPublic = true
    public var isFriend = false
    public var isFamily = false
    public var changesPermissions = false
    public var comment = LibraryPhoto.Audience.everybody
    public var addMeta = LibraryPhoto.Audience.contacts

    public var safetyField = SafetyField.safety
    public var safety = UploadMetadata.Safety.safe
    public var contentType = UploadMetadata.ContentType.photo
    public var hidden = false

    public var licence = License.allRightsReserved

    public var dateMode = DateMode.shift
    public var shiftHours = 0
    public var shiftMinutes = 0
    public var shiftsEarlier = false
    public var takenText = ""

    public var locationMode = LocationMode.set
    /// 0,0 until a place is chosen; that point is open sea, never a choice.
    public var latitude = 0.0
    public var longitude = 0.0
    public var accuracy = 16
    public var geoIsPublic = true
    public var geoIsContact = false
    public var geoIsFriend = false
    public var geoIsFamily = false

    public init(kind: EditKind) { self.kind = kind }

    /// Nil when the form is not yet a valid edit; `problem` says why.
    public var edits: [PhotoEdit]? {
        if case let .success(edits) = validated { return edits }
        return nil
    }

    public var problem: String? {
        if case let .failure(problem) = validated { return problem.message }
        return nil
    }

    var tags: [String] {
        tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var shiftSeconds: Int { (shiftHours * 3600 + shiftMinutes * 60) * (shiftsEarlier ? -1 : 1) }

    struct Problem: Error, Equatable { let message: String }
}
