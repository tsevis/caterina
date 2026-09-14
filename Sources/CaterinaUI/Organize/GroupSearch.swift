import Foundation

/// Finding a group by name as people type it.
public enum GroupSearch {

    /// Every word typed starts a word of the name, ignoring case and
    /// accents: "street photo" finds "Street Photography – Europe".
    public static func matches(_ name: String, query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return true }
        let have = words(name)
        return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
