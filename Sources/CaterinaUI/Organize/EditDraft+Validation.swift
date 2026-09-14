import Foundation

import FlickrKit

extension EditDraft {

    var validated: Result<[PhotoEdit], Problem> {
        switch kind {
        case .title, .description: text(for: kind)
        case .tags: tagEdits
        case .visibility: .success(visibilityEdits)
        case .safety: .success([safetyEdit])
        case .licence: .success([.setLicense(licence)])
        case .dateTaken: dateEdit
        case .location: locationEdit
        case .datePosted: postedEdit
        case .rotate, .people: .failure(Problem(message: ""))
        }
    }

    private func text(for kind: EditKind) -> Result<[PhotoEdit], Problem> {
        switch (kind, textMode) {
        case (_, .append) where text.isEmpty: .failure(Problem(message: "Enter the text to add."))
        case (_, .set) where text.isEmpty && !clearsText:
            .failure(Problem(message: "Enter the text, or choose to clear it."))
        case (.title, .set): .success([.setTitle(text)])
        case (.title, .append): .success([.appendToTitle(text)])
        case (_, .set): .success([.setDescription(text)])
        case (_, .append): .success([.appendToDescription(text)])
        }
    }

    private var tagEdits: Result<[PhotoEdit], Problem> {
        if tagMode == .rename {
            let (from, to) = (renameFrom.trimmed, renameTo.trimmed)
            guard !from.isEmpty, !to.isEmpty else {
                return .failure(Problem(message: "Enter the tag to rename and its new name."))
            }
            return .success([.renameTag(from: from, to: to)])
        }
        guard !tags.isEmpty else { return .failure(Problem(message: "Enter at least one tag.")) }
        switch tagMode {
        case .add: return .success([.addTags(tags)])
        case .remove: return .success([.removeTags(tags)])
        case .replace, .rename: return .success([.replaceTags(tags)])
        }
    }

    /// Flickr stores public photos without friend and family flags.
    private var visibilityEdits: [PhotoEdit] {
        let visibility = LibraryPhoto.Visibility(isPublic: isPublic, isFriend: !isPublic && isFriend,
                                                 isFamily: !isPublic && isFamily)
        let permissions: [PhotoEdit] = changesPermissions
            ? [.setPermissions(.init(comment: comment, addMeta: addMeta))] : []
        return [.setVisibility(visibility)] + permissions
    }

    private var safetyEdit: PhotoEdit {
        switch safetyField {
        case .safety: .setSafety(safety)
        case .contentType: .setContentType(contentType)
        case .hidden: .setHiddenFromSearch(hidden)
        }
    }

    private var dateEdit: Result<[PhotoEdit], Problem> {
        switch dateMode {
        case .shift:
            guard shiftSeconds != 0 else { return .failure(Problem(message: "Enter how far to shift the date.")) }
            return .success([.shiftTaken(seconds: shiftSeconds)])
        case .set:
            let taken = takenText.trimmingCharacters(in: .whitespaces)
            guard PhotoEdit.isValidTaken(taken) else {
                return .failure(Problem(message: "Write the date as 2024-06-01 21:14:05."))
            }
            return .success([.setTaken(taken)])
        }
    }

    private var postedEdit: Result<[PhotoEdit], Problem> {
        switch postedMode {
        case .shift:
            guard postedShiftDays != 0 else { return .failure(Problem(message: "Enter how many days to shift it.")) }
            return .success([.shiftPosted(seconds: postedShiftDays * 86_400)])
        case .set:
            guard let postedDate else { return .failure(Problem(message: "Choose the date it was posted.")) }
            guard postedDate <= Date() else {
                return .failure(Problem(message: "Flickr does not take a posted date in the future."))
            }
            return .success([.setPosted(Date(timeIntervalSince1970: postedDate.timeIntervalSince1970.rounded(.down)))])
        }
    }

    private var locationEdit: Result<[PhotoEdit], Problem> {
        switch locationMode {
        case .remove: return .success([.removeLocation])
        case .privacy:
            return .success([.setGeoPermissions(.init(isPublic: geoIsPublic, isContact: geoIsContact,
                                                      isFriend: geoIsFriend, isFamily: geoIsFamily))])
        case .set:
            guard latitude.isFinite, longitude.isFinite, latitude != 0 || longitude != 0,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                return .failure(Problem(message: "Choose a place on the map."))
            }
            return .success([.setLocation(.init(latitude: latitude, longitude: longitude,
                                                 accuracy: min(max(accuracy, 1), 16)))])
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
