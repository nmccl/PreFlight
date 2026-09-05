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
            Tab("Methodology", systemImage: "info.bubble") {
                MethodologySettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .frame(width: 500, height: 460)
    }
}

private struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        @Bindable var purchases = appState.purchases
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(SettingsService.Appearance.allCases, id: \.self) { appearance in
                    Text(appearance.displayName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Apple Intelligence summaries", isOn: $settings.isAIEnabled)
            Toggle("Send anonymous usage analytics", isOn: $settings.isAnalyticsEnabled)

            #if DEBUG
            Section {
                Toggle("Simulate Pro Unlock", isOn: $purchases.devOverrideEnabled)
            } header: {
                Label("Developer", systemImage: "hammer")
            } footer: {
                Text("Bypasses StoreKit to test Pro features without a real transaction. Disable before testing the actual purchase flow.")
            }
            Button("Reset Onboarding") {
                appState.settings.hasCompletedOnboarding = false
            }
            #endif
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
                        AnalyticsService.shared.ascCredentialsRemoved()
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
            AnalyticsService.shared.ascCredentialsConnected()
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

private struct MethodologySettingsPane: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                methodologySection(
                    icon: "doc.text.magnifyingglass",
                    title: "How Findings Are Generated",
                    body: "Every finding comes from deterministic analysis of your project files — build settings, source code, Info.plist, PrivacyInfo.xcprivacy, StoreKit config, and live App Store Connect metadata. AI is only used to write the Summary at the top of your report; it never invents or modifies findings."
                )
                methodologySection(
                    icon: "checkmark.seal",
                    title: "Facts vs. Heuristics",
                    body: "Each finding is marked Fact or Heuristic.\n\n• Fact — derived from a verifiable value: a build setting, a plist key, a missing file, or a live ASC API response.\n\n• Heuristic — inferred from a source-code pattern that correlates with an issue but cannot be proven without running the app."
                )
                methodologySection(
                    icon: "shield.lefthalf.filled",
                    title: "Severity Clamping",
                    body: "A heuristic finding can never appear as Critical — severity is automatically capped at Warning. This keeps source-scan inferences from looking more authoritative than they are. If a finding is Critical, it is always a verified fact."
                )
                methodologySection(
                    icon: "checkmark.circle",
                    title: "What PreFlight Checks",
                    body: "• Project config: bundle ID, version strings, entitlements, build settings\n• Privacy: usage strings, PrivacyInfo.xcprivacy, SDK declarations vs. ASC nutrition label\n• StoreKit: paywall completeness, restore path, config consistency\n• App Review heuristics: external payment links, demo credentials, metadata\n• Accessibility: Dynamic Type, VoiceOver labels, Reduce Motion\n• Device Support: iPad multitasking, Mac Catalyst readiness\n• Metadata (Pro): live ASC screenshots, review notes, subscription groups, EULA"
                )
                methodologySection(
                    icon: "xmark.circle",
                    title: "What PreFlight Cannot Check",
                    body: "• Runtime behavior — PreFlight never executes your app\n• Simulator flows — Restore Purchases, Sign in with Apple, account deletion require manual testing\n• Subjective reviewer judgment — sections like 4.2 (Minimum Functionality) require human review\n• Content appropriateness, copyright, and IP issues\n\nSee the \"Not Verified by PreFlight\" checklist at the bottom of each report."
                )
            }
            .padding(20)
        }
    }

    private func methodologySection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        URL(string: "mailto:contact@noahmcclung.com")
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
