import AppKit
import SwiftUI

import FlickrKit

/// Where the API key goes, and the sign-in button beside it.
///
/// One form, used by Settings and by the first-launch sheet, so there is one
/// place credentials are entered and one place they are validated.
struct CredentialsForm: View {
    @Bindable var model: AppModel
    /// The first-launch sheet explains itself; Settings does not need to.
    let isOnboarding: Bool
    var onFinished: () -> Void = {}

    @State private var key = ""
    @State private var secret = ""
    @State private var problem: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isOnboarding {
                Text("A Flickr API key")
                    .font(.title3.weight(.semibold))
                Text("""
                Flickr gives every application its own key. Getting one takes a \
                minute and costs nothing; it is what lets this ask Flickr for \
                photos on your behalf. The key and its secret are kept in your \
                Keychain and are never written anywhere else.
                """)
                .font(.callout)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Link("Create a key at flickr.com",
                     destination: URL(string: "https://www.flickr.com/services/apps/create/")!)
                    .font(.callout)
            }

            Form {
                TextField("API key", text: $key)
                SecureField("API secret", text: $secret)
            }
            .formStyle(.columns)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if model.isSignedIn {
                    Label(model.account?.username ?? "Signed in",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.inkSecondary)
                    Button("Sign Out") { signOut() }
                } else {
                    Button("Sign In to Flickr…") { signIn() }
                        .disabled(isWorking || !canSave)
                    if isWorking { ProgressView().controlSize(.small) }
                }

                Spacer()

                Button(isOnboarding ? "Save and Continue" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(isOnboarding ? 24 : 0)
        .frame(width: isOnboarding ? 460 : nil)
        .onAppear(perform: fill)
    }

    private var canSave: Bool {
        !key.trimmed.isEmpty && !secret.trimmed.isEmpty
    }

    private func fill() {
        guard let credentials = model.credentials() else { return }
        key = credentials.consumerKey
        secret = credentials.consumerSecret
    }

    private func save() {
        do {
            try model.saveAPIKey(key: key, secret: secret)
            problem = nil
            onFinished()
        } catch {
            problem = (error as? FlickrError)?.message ?? error.localizedDescription
        }
    }

    /// Saving first: signing in needs the key that is in the fields, not the one
    /// that was in the Keychain when the window opened.
    private func signIn() {
        do {
            try model.saveAPIKey(key: key, secret: secret)
        } catch {
            problem = (error as? FlickrError)?.message ?? error.localizedDescription
            return
        }
        guard let credentials = model.credentials(),
              let anchor = NSApp.keyWindow ?? NSApp.windows.first else { return }

        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            do {
                let account = try await FlickrSignIn.run(credentials: credentials, anchor: anchor)
                try model.signedIn(account)
                onFinished()
            } catch {
                problem = (error as? FlickrError)?.message ?? error.localizedDescription
            }
        }
    }

    private func signOut() {
        do {
            try model.signOut()
        } catch {
            problem = (error as? FlickrError)?.message ?? error.localizedDescription
        }
    }
}

/// ⌘, — the API key, and the account it belongs to.
public struct SettingsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        TabView {
            Form {
                Section("Flickr account") {
                    CredentialsForm(model: model, isOnboarding: false)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 520, height: 320)
    }
}
