import Foundation

/// Checks whether the app's text and controls behave like an accessible
/// Apple app: Dynamic Type support and VoiceOver labels. Everything here is
/// inferred from source text, so all findings are observations.
struct AccessibilityAnalyzer: Analyzer {
    let category = AnalysisCategory.accessibility

    /// Font constructions that pin text to a fixed point size.
    private static let fixedFontPatterns = [
        ".font(.system(size:",
        "Font.system(size:",
        "UIFont.systemFont(ofSize:",
        "NSFont.systemFont(ofSize:",
    ]

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        guard !context.sourceFileURLs.isEmpty else {
            return .skipped(category, reason: "No source files found to inspect.")
        }

        let source = context.combinedSource()
        var findings: [Finding] = []
        var checks = 0

        checks += 1
        let fixedFontCount = Self.fixedFontPatterns.reduce(0) { count, pattern in
            count + occurrences(of: pattern, in: source)
        }
        if fixedFontCount > 0 {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                title: "Text may not scale with Dynamic Type",
                detail: "The code sets fixed point sizes on fonts instead of using text styles, so that text won't grow when users raise their preferred text size.",
                whyItMatters: "Dynamic Type support is part of Apple's accessibility expectations — fixed-size text leaves the app unusable for people who rely on larger text, and it shows up in the accessibility nutrition label.",
                evidence: "Found \(fixedFontCount) fixed-size font construction(s), e.g. \(Self.fixedFontPatterns[0])...).",
                suggestedFix: "Use text styles (.font(.body), .title, ...) or scale custom fonts with UIFontMetrics / relativeTo:.",
                estimatedFixMinutes: 30
            ))
        }

        checks += 1
        let usesSymbolButtons = source.contains("Image(systemName:") && source.contains("Button")
        if usesSymbolButtons && !source.contains("accessibilityLabel") {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                title: "No accessibility labels found",
                detail: "The app appears to use icon-only controls, but no accessibilityLabel modifier was found anywhere in the source.",
                whyItMatters: "VoiceOver reads a label for every control; icon-only buttons without one are announced as unhelpful noise, making the app hard to use with a screen reader.",
                evidence: "Found \"Image(systemName:\" and \"Button\" in source; no \"accessibilityLabel\" reference found.",
                suggestedFix: "Add .accessibilityLabel(...) to icon-only buttons and images that convey meaning, or use Label so text and icon travel together.",
                estimatedFixMinutes: 30
            ))
        }

        checks += 1
        let hasCustomViewSubclass = source.contains(": UIControl") || source.contains(": NSControl")
            || source.contains(": UIView") || source.contains(": NSView")
        let hasTraitSetup = source.contains("accessibilityTraits") || source.contains("accessibilityRole")
            || source.contains(".accessibilityAddTraits") || source.contains(".accessibilityRemoveTraits")
        if hasCustomViewSubclass && !hasTraitSetup {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                title: "Custom view subclass may lack VoiceOver traits",
                detail: "A custom view or control subclass was found (UIView, UIControl, NSView, or NSControl), but no accessibility trait assignment appears in the source. VoiceOver needs traits to announce the purpose of interactive elements.",
                whyItMatters: "Without traits, VoiceOver announces interactive custom views as static elements, making them effectively inaccessible. This surfaces in the VoiceOver nutrition label.",
                evidence: "Found a custom view subclass but no accessibilityTraits, accessibilityRole, or .accessibilityAddTraits() call.",
                suggestedFix: "Set accessibilityTraits = .button (or the appropriate trait) on interactive custom views. In SwiftUI, use .accessibilityAddTraits(.isButton).",
                estimatedFixMinutes: 20
            ))
        }

        checks += 1
        let hasTextFields = source.contains("TextField(") || source.contains("UITextField")
        let hasKeyboardType = source.contains("keyboardType") || source.contains(".numberPad")
            || source.contains(".emailAddress") || source.contains(".decimalPad") || source.contains(".phonePad")
        if hasTextFields && !hasKeyboardType {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .observation,
                title: "Text fields may be missing keyboard type",
                detail: "Text fields were found in source without an explicit keyboard type modifier. Presenting a generic keyboard for numeric, email, or phone inputs creates unnecessary friction.",
                whyItMatters: "Apple expects apps to present the most contextually appropriate keyboard for each input field — it's part of the accessibility and usability bar reviewers apply.",
                evidence: "\"TextField(\" or \"UITextField\" found; no .keyboardType, .numberPad, .emailAddress, or similar modifier found.",
                suggestedFix: "Add .keyboardType(.emailAddress), .keyboardType(.numberPad), or the appropriate type to each field based on its expected input.",
                estimatedFixMinutes: 15
            ))
        }

        checks += 1
        let hasAnimations = source.contains("withAnimation(") || source.contains(".animation(")
        let respectsReduceMotion = source.contains("accessibilityReduceMotion") || source.contains("reduceMotion")
            || source.contains("isReduceMotionEnabled")
        if hasAnimations && !respectsReduceMotion {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .observation,
                title: "Animations may not respect Reduce Motion",
                detail: "The app uses animations, but no Reduce Motion check was found. Users who enable Reduce Motion expect motion to be minimized or substituted with a cross-fade.",
                whyItMatters: "Ignoring Reduce Motion is a documented accessibility failure that shows up in the accessibility nutrition label and can cause discomfort for users with vestibular disorders.",
                evidence: "Found withAnimation() or .animation(); no accessibilityReduceMotion or isReduceMotionEnabled reference found.",
                suggestedFix: "Read @Environment(\\.accessibilityReduceMotion) and substitute cross-fades or instant transitions when it is true.",
                estimatedFixMinutes: 20
            ))
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    private func occurrences(of pattern: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: pattern, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
