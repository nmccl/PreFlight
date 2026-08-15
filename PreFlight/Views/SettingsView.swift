import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("App Store Connect", systemImage: "key") {
                AppStoreConnectSettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(SettingsService.Appearance.allCases, id: \.self) { appearance in
                    Text(appearance.displayName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Apple Intelligence summaries", isOn: $settings.isAIEnabled)
        }
        .formStyle(.grouped)
    }
}

/// API key entry: the two identifiers go to UserDefaults; the .p8 contents
/// go to the Keychain and never leave this Mac.
private struct AppStoreConnectSettingsPane: View {
    @Environment(AppState.self) private var appState
    @State private var isImportingKey = false
    @State private var importError: String?

    private var keyTypes: [UTType] {
        [UTType(filenameExtension: "p8", conformingTo: .data), .data].compactMap { $0 }
    }

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                TextField("Issuer ID", text: $settings.ascIssuerID, prompt: Text("69a6de70-03db-47e3-e053-5b8c7c11a4d1"))
                TextField("Key ID", text: $settings.ascKeyID, prompt: Text("2X9R4HXF34"))

                if settings.ascKeyStored {
                    LabeledContent("Private Key") {
                        Label("Stored in Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Remove Key…", role: .destructive) {
                        settings.removePrivateKey()
                    }
                } else {
                    LabeledContent("Private Key") {
                        Button("Import .p8 Key…") {
                            isImportingKey = true
                        }
                    }
                }
            } footer: {
                Text("Create an API key with Developer access under Users and Access > Integrations in App Store Connect. PreFlight only reads metadata; it never modifies your apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImportingKey, allowedContentTypes: keyTypes) { result in
            switch result {
            case .success(let url):
                importKey(at: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't Import Key", isPresented: isShowingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "An unknown error occurred.")
        }
    }

    private func importKey(at url: URL) {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let pem = try String(contentsOf: url, encoding: .utf8)
            guard pem.contains("BEGIN PRIVATE KEY") else {
                importError = "That file doesn't look like an App Store Connect .p8 private key."
                return
            }
            try appState.settings.storePrivateKey(pem)
        } catch {
            importError = error.localizedDescription
        }
    }

    private var isShowingImportError: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }
}

private struct AboutSettingsPane: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var websiteURL: URL? {
        URL(string: "https://preflight.info")
    }

    private var contactURL: URL? {
        URL(string: "mailto:noah_mcclung@icloud.com")
    }

    private var privacyURL: URL? {
        URL(string: "https://preflight.info/privacy")
    }

    private var termsURL: URL? {
        URL(string: "https://preflight.info/terms")
    }

    var body: some View {
        Form {
            LabeledContent("Version", value: appVersion)
            if let contactURL {
                Link("Contact Support", destination: contactURL)
            }
            if let websiteURL {
                Link(destination: websiteURL) {
                    Label("Website", systemImage: "globe")
                }
            }
            if let privacyURL {
                Link(destination: privacyURL) {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
            }
            if let termsURL {
                Link(destination: termsURL) {
                    Label("Terms and Conditions", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
    }
}
