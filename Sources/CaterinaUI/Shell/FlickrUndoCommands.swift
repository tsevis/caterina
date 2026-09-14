import SwiftUI

/// Undo for the last Flickr edit, in the Edit menu.
///
/// **⌥⌘Z, not ⌘Z.** ⌘Z belongs to the text fields in the edit form; sharing it
/// would turn undoing a typo into rewriting hundreds of photos. And it asks
/// first, since a key is easy to press by mistake.
public struct FlickrUndoCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(after: .undoRedo) {
            Divider()
            Button(title) {
                model.tab = .organize
                model.organize?.requestUndo()
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(model.organize?.newestUndoable == nil || model.organize?.isBusy == true)
        }
    }

    private var title: String {
        guard let edit = model.organize?.newestUndoable else { return "Undo Flickr Edit…" }
        return "Undo “\(edit.batch.title)” on Flickr…"
    }
}
