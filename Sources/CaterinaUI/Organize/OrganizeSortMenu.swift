import SwiftUI

import CaterinaLibrary

/// How the photos in the grid are ordered.
struct OrganizeSortMenu: View {
    let organize: OrganizeModel

    private var choice: Binding<LibraryOrder> {
        Binding(get: { organize.order }, set: { organize.sort(by: $0) })
    }

    var body: some View {
        Picker("Sort", selection: choice) {
            ForEach(LibraryOrder.allCases, id: \.self) { Text($0.sortTitle).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("Choose the order of your photos")
    }
}
