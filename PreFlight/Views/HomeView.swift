import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Project selection: open a new project or jump back into a recent one.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isChoosingProject = false

    private var projectTypes: [UTType] {
        [UTType(filenameExtension: "xcodeproj", conformingTo: .package)].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroCard
                recentsSection
            }
            .padding(28)
        }
        .navigationTitle("My Projects")
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
        }
        .fileImporter(
            isPresented: $isChoosingProject,
            allowedContentTypes: projectTypes
        ) { result in
            switch result {
            case .success(let url):
                appState.openProject(at: url)
            case .failure(let error):
                appState.errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't Open Project", isPresented: isShowingError) {
            Button("OK") {}
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var heroCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Analyze a Project")
                    .font(.title2.bold())
                Text("Open an Xcode project to check its App Store review readiness.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Project…") {
                isChoosingProject = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(24)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recents")
                .font(.title3.bold())

            if appState.recents.recents.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Projects", systemImage: "clock")
                } description: {
                    Text("Projects you open will appear here.")
                }
                .frame(maxWidth: .infinity)
            } else {
                GlassEffectContainer(spacing: 16) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(appState.recents.recents) { recent in
                            RecentProjectCard(recent: recent)
                        }
                    }
                }
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }
}

/// One App Store Connect-style card: icon, name, bundle id, last opened,
/// and readiness from the most recent analysis.
private struct RecentProjectCard: View {
    @Environment(AppState.self) private var appState
    let recent: RecentProject

    var body: some View {
        Button {
            appState.openRecent(recent)
        } label: {
            HStack(spacing: 14) {
                ProjectIconView(imageData: recent.appIconImageData)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recent.name)
                        .font(.headline)
                    if let bundleIdentifier = recent.bundleIdentifier {
                        Text(bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("Opened \(recent.lastOpened, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                ReadinessBadge(score: recent.lastScore)
            }
            .padding(16)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                appState.recents.remove(recent)
            }
        }
    }
}

/// Mini score ring, or a placeholder before the first analysis.
private struct ReadinessBadge: View {
    let score: Int?

    var body: some View {
        if let score {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(score) / 100)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(score)%")
                        .font(.caption2.bold())
                        .monospacedDigit()
                }
                .frame(width: 42, height: 42)

                Text("Ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Not analyzed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var ringColor: Color {
        switch score ?? 0 {
        case ..<60: .red
        case ..<85: .orange
        default: .green
        }
    }
}

/// Renders stored icon PNG data, falling back to a placeholder glyph.
private struct ProjectIconView: View {
    let imageData: Data?

    var body: some View {
        if let imageData, let image = platformImage(from: imageData) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "app.dashed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #elseif canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
