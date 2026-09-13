import Foundation

import FlickrKit

extension EditDraft {

    /// What the Activity panel calls the batch.
    public var batchTitle: String {
        switch kind {
        case .title: textMode == .set ? "Set title to “\(text)”" : "Add “\(text)” to titles"
        case .description: textMode == .set ? "Set description" : "Add to descriptions"
        case .tags: tagTitle
        case .visibility: "Change who can see"
        case .safety: safetyTitle
        case .licence: "Set licence to \(licence.label)"
        case .dateTaken: dateTitle
        case .location: locationTitle
        }
    }

    private var tagTitle: String {
        let list = tags.joined(separator: ", ")
        switch tagMode {
        case .add: return "Add tags: \(list)"
        case .remove: return "Remove tags: \(list)"
        case .replace: return "Replace tags with: \(list)"
        case .rename: return "Rename tag \(renameFrom) to \(renameTo)"
        }
    }

    private var safetyTitle: String {
        switch safetyField {
        case .safety: "Set safety level"
        case .contentType: "Set content type"
        case .hidden: hidden ? "Hide from public search" : "Show in public search"
        }
    }

    private var dateTitle: String {
        guard dateMode == .shift else { return "Set date taken to \(takenText)" }
        let parts = [shiftHours > 0 ? "\(shiftHours) h" : nil, shiftMinutes > 0 ? "\(shiftMinutes) min" : nil]
        return "Shift date taken \(parts.compactMap { $0 }.joined(separator: " ")) \(shiftsEarlier ? "earlier" : "later")"
    }

    private var locationTitle: String {
        switch locationMode {
        case .set: "Set location"
        case .remove: "Remove location"
        case .privacy: "Change who can see the location"
        }
    }
}
