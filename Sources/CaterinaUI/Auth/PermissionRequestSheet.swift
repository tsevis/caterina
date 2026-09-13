import AppKit
import SwiftUI

import FlickrKit

/// Asking Flickr for more than the current sign-in allows, at the moment
/// something the person just did needs it.
struct PermissionRequestSheet: View {
    let model: AppModel
    let permission: FlickrPermission
    /// Called once Flickr has approved and the app holds the new token.
    let onApproved: () async -> Void
    let onCancel: () -> Void

    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: permission == .delete ? "trash" : "pencil.and.outline")
                .font(.headline)
            Text(permission.reason)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Flickr opens in a browser window. Approve there and you come straight back here.")
                .font(.callout)
                .foregroundStyle(Theme.inkSecondary)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isWorking ? "Waiting for Flickr…" : "Approve on Flickr…", action: approve)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var title: String {
        switch permission {
        case .read: "Sign in to Flickr"
        case .write: "Allow Caterina to change your photos"
        case .delete: "Allow Caterina to delete photos"
        }
    }

    private func approve() {
        guard let credentials = model.credentials(),
              let anchor = NSApp.keyWindow ?? NSApp.windows.first else {
            problem = "Enter your API key in Settings first."
            return
        }
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            do {
                let account = try await FlickrSignIn.run(credentials: credentials, permission: permission,
                                                         anchor: anchor)
                try await model.signedIn(account)
                await onApproved()
            } catch {
                problem = (error as? FlickrError)?.message ?? error.localizedDescription
            }
        }
    }
}
