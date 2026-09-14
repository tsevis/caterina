import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The fields for one kind of edit.
struct EditForm: View {
    @Binding var draft: EditDraft
    var organize: OrganizeModel?

    var body: some View {
        switch draft.kind {
        case .title, .description: textForm
        case .tags: tagForm
        case .visibility: VisibilityForm(draft: $draft)
        case .safety: safetyForm
        case .licence:
            Picker("Licence", selection: $draft.licence) {
                ForEach(License.allCases) { Text($0.label).tag($0) }
            }
        case .dateTaken: dateForm
        case .location: LocationForm(draft: $draft)
        case .datePosted: PostedForm(draft: $draft)
        case .rotate:
            Picker("Rotate", selection: $draft.degrees) {
                Text("90° clockwise").tag(90)
                Text("180°").tag(180)
                Text("90° anticlockwise").tag(270)
            }
            .pickerStyle(.radioGroup)
        case .people: PeopleForm(draft: $draft, organize: organize)
        }
    }

    private var textForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.textMode) {
                Text("Replace").tag(EditDraft.TextMode.set)
                Text("Add to the end").tag(EditDraft.TextMode.append)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if draft.textMode == .set && draft.text.isEmpty {
                Toggle("Clear them", isOn: $draft.clearsText)
            }
            if draft.kind == .description {
                TextEditor(text: $draft.text).frame(minHeight: 80).font(.body)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
            } else {
                TextField("Title", text: $draft.text).textFieldStyle(.roundedBorder)
            }
            Text("Placeholders: \(TitlePattern.placeholders.joined(separator: " ")). "
                 + "{n} counts through the tray in order; {nn} pads it so titles sort.")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.tagMode) {
                Text("Add").tag(EditDraft.TagMode.add)
                Text("Remove").tag(EditDraft.TagMode.remove)
                Text("Replace").tag(EditDraft.TagMode.replace)
                Text("Rename").tag(EditDraft.TagMode.rename)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if draft.tagMode == .rename {
                TextField("Tag", text: $draft.renameFrom).textFieldStyle(.roundedBorder)
                TextField("New name", text: $draft.renameTo).textFieldStyle(.roundedBorder)
                Text("Renames the tag on the photos in the tray. To rename it everywhere, "
                     + "put the tag's view in the tray first.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("New York, blue hour, film", text: $draft.tagText).textFieldStyle(.roundedBorder)
                Text(tagHint).font(.caption).foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tagHint: String {
        switch draft.tagMode {
        case .replace: "Separate tags with commas. Tags added on flickr.com since the last sync are kept."
        default: "Separate tags with commas. Spelling is kept as you type it."
        }
    }

    private var safetyForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.safetyField) {
                Text("Safety level").tag(EditDraft.SafetyField.safety)
                Text("Content type").tag(EditDraft.SafetyField.contentType)
                Text("Search").tag(EditDraft.SafetyField.hidden)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch draft.safetyField {
            case .safety:
                Picker("Safety level", selection: $draft.safety) {
                    Text("Safe").tag(UploadMetadata.Safety.safe)
                    Text("Moderate").tag(UploadMetadata.Safety.moderate)
                    Text("Restricted").tag(UploadMetadata.Safety.restricted)
                }
            case .contentType:
                Picker("Content type", selection: $draft.contentType) {
                    Text("Photo").tag(UploadMetadata.ContentType.photo)
                    Text("Screenshot").tag(UploadMetadata.ContentType.screenshot)
                    Text("Art or illustration").tag(UploadMetadata.ContentType.other)
                    Text("Virtual photography").tag(UploadMetadata.ContentType.virtualPhotography)
                }
            case .hidden:
                Toggle("Hide from public search", isOn: $draft.hidden)
            }
        }
    }

    private var dateForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.dateMode) {
                Text("Shift").tag(EditDraft.DateMode.shift)
                Text("Set").tag(EditDraft.DateMode.set)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if draft.dateMode == .shift {
                HStack {
                    Stepper("\(draft.shiftHours) h", value: $draft.shiftHours, in: 0...48)
                    Stepper("\(draft.shiftMinutes) min", value: $draft.shiftMinutes, in: 0...59, step: 15)
                }
                Picker("", selection: $draft.shiftsEarlier) {
                    Text("Later").tag(false)
                    Text("Earlier").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("For a camera clock set to the wrong time zone. Photos with no date taken are left alone.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("2024-06-01 21:14:05", text: $draft.takenText).textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
        }
    }
}

/// Who can see, and optionally who can comment and add tags.
struct VisibilityForm: View {
    @Binding var draft: EditDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Public", isOn: $draft.isPublic)
            Toggle("Friends", isOn: $draft.isFriend).disabled(draft.isPublic).padding(.leading, 18)
            Toggle("Family", isOn: $draft.isFamily).disabled(draft.isPublic).padding(.leading, 18)
            Divider()
            Toggle("Also change who can comment and add tags", isOn: $draft.changesPermissions)
            if draft.changesPermissions {
                audiencePicker("Who can comment", $draft.comment)
                audiencePicker("Who can add notes and tags", $draft.addMeta)
            }
        }
    }

    private func audiencePicker(_ title: String, _ selection: Binding<LibraryPhoto.Audience>) -> some View {
        Picker(title, selection: selection) {
            Text("Only you").tag(LibraryPhoto.Audience.nobody)
            Text("Friends & family").tag(LibraryPhoto.Audience.friendsAndFamily)
            Text("Contacts").tag(LibraryPhoto.Audience.contacts)
            Text("Any Flickr member").tag(LibraryPhoto.Audience.everybody)
        }
    }
}

/// The date photos show as posted: shifted by days, or set.
struct PostedForm: View {
    @Binding var draft: EditDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.postedMode) {
                Text("Shift").tag(EditDraft.DateMode.shift)
                Text("Set").tag(EditDraft.DateMode.set)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if draft.postedMode == .shift {
                Stepper("\(draft.postedShiftDays) days", value: $draft.postedShiftDays, in: -3650...3650)
            } else {
                DatePicker("Posted", selection: Binding(get: { draft.postedDate ?? Date() },
                                                        set: { draft.postedDate = $0 }), in: ...Date())
                    .onAppear { if draft.postedDate == nil { draft.postedDate = Date() } }
            }
            Text("Changes where photos fall in your photostream. Flickr refuses a date in the future.")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tag or untag a Flickr member in every photo in the tray.
struct PeopleForm: View {
    @Binding var draft: EditDraft
    var organize: OrganizeModel?
    @State private var isFinding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.removesPerson) {
                Text("Tag").tag(false)
                Text("Untag").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                TextField("Username, photostream address or NSID", text: $draft.person).textFieldStyle(.roundedBorder)
                Button(isFinding ? "Finding…" : "Find") {
                    guard let organize else { return }
                    isFinding = true
                    let query = draft.personQuery
                    Task {
                        let found = await organize.lookUpPerson(query)
                        if draft.personQuery == query { draft.resolvedPerson = found }
                        isFinding = false
                    }
                }
                .disabled(draft.personQuery.isEmpty || isFinding || organize == nil)
            }
            if let found = draft.resolvedPerson {
                Label("\(found.username) (\(found.nsid))", systemImage: "person.crop.circle.badge.checkmark")
            }
            Text("Flickr allows tagging only people who let you, and not in private photos; "
                 + "those photos are listed in Activity.")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
