import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

/// Renders a project's stored icon PNG data, falling back to the system's
/// generic application icon. Shared by the Home cards and the project detail page.
struct ProjectIconView: View {
    let imageData: Data?
    var cornerRadius: CGFloat = 10
    var symbolSize: CGFloat = 18

    var body: some View {
        if let imageData, let image = platformImage(from: imageData) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: cornerRadius))
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        #if canImport(AppKit)
        Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius))
        #else
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(.tertiary.opacity(0.7))
                        RoundedRectangle(cornerRadius: 3).fill(.tertiary.opacity(0.45))
                    }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(.tertiary.opacity(0.45))
                        RoundedRectangle(cornerRadius: 3).fill(.tertiary.opacity(0.25))
                    }
                }
                .padding(symbolSize * 0.4)
            }
        #endif
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
