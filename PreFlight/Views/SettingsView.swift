import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .frame(width: 440, height: 300)
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
