import Foundation

import FlickrKit

/// A named set of choices photos are uploaded with.
public struct UploadPreset: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let metadata: UploadMetadata

    public init(id: UUID = UUID(), name: String, metadata: UploadMetadata) {
        self.id = id
        self.name = name
        self.metadata = metadata
    }

    /// Always there, and not editable: who can see a photo is the choice every
    /// upload makes.
    public static let builtIn: [UploadPreset] = [
        UploadPreset(id: UUID(uuidString: "6F1C0A36-0000-4000-8000-000000000001")!, name: "Public",
                     metadata: UploadMetadata(visibility: .init(isPublic: true, isFriend: false, isFamily: false))),
        UploadPreset(id: UUID(uuidString: "6F1C0A36-0000-4000-8000-000000000002")!, name: "Friends & family",
                     metadata: UploadMetadata(visibility: .init(isPublic: false, isFriend: true, isFamily: true))),
        UploadPreset(id: UUID(uuidString: "6F1C0A36-0000-4000-8000-000000000003")!, name: "Private",
                     metadata: UploadMetadata(visibility: .init(isPublic: false, isFriend: false, isFamily: false),
                                              hiddenFromSearch: true)),
    ]
}

/// Presets the person made, in preferences. Not secret, so not the Keychain.
public struct UploadPresetStore: Sendable {
    private static let key = "UploadPresets"
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The built-in presets, then the person's own.
    public func load() -> [UploadPreset] {
        let custom = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([UploadPreset].self, from: $0) } ?? []
        return UploadPreset.builtIn + custom.filter { preset in !UploadPreset.builtIn.contains { $0.id == preset.id } }
    }

    /// Store the person's own presets; built-ins are never written.
    public func save(_ presets: [UploadPreset]) {
        let custom = presets.filter { preset in !UploadPreset.builtIn.contains { $0.id == preset.id } }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
