import Foundation

import CaterinaLibrary

/// Views saved by name, like smart albums, kept in the library copy.
extension OrganizeModel {

    static let savedViewsKey = "organize.savedViews"

    public func saveView(named name: String, scope: OrganizeScope? = nil) {
        let name = name.trimmed
        guard !name.isEmpty else { return }
        let view = SavedView(name: name, scope: scope ?? self.scope)
        writeSavedViews(savedViews.filter { $0.name != name } + [view])
    }

    public func deleteView(named name: String) {
        writeSavedViews(savedViews.filter { $0.name != name })
    }

    func readSavedViews() -> [SavedView] {
        do {
            guard let data = try store.setting(Self.savedViewsKey) else { return [] }
            return try JSONDecoder().decode([SavedView].self, from: data)
        } catch {
            problem = "Could not read your saved views: \(Self.message(error))"
            return []
        }
    }

    private func writeSavedViews(_ views: [SavedView]) {
        do {
            try store.setSetting(Self.savedViewsKey, to: try JSONEncoder().encode(views))
            savedViews = views
        } catch {
            problem = "Could not save the view: \(Self.message(error))"
        }
    }
}
