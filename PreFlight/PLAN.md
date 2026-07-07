# Developer Companion — MVP Implementation Plan

## Context

Developer Companion is a macOS-first SwiftUI app that analyzes a user's Xcode project for App Store review readiness. It runs five analyzers, produces a Release Readiness score out of 100 with per-category scores and findings (severity, title, description, suggested fix, estimated fix time), and generates an on-device AI summary via Apple Intelligence. The MVP flow: Onboarding → Home (open project + recents) → Project view → animated analysis → Results → Settings.

**Current state:** All 28 Swift files under `Developer Companion/Developer Companion/` are empty stubs — folder structure and file names exist, zero implementation. Build config: SDK 27, deployment target 27.0, `ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`, `GENERATE_INFOPLIST_FILE = YES`, multiplatform (macOS/iOS/visionOS). No test target.

**User decisions:**
- **Metadata analyzer:** full App Store Connect API integration (user supplies ASC API key).
- **Platform:** macOS-first; validate only on macOS for v1, but keep code multiplatform-friendly (pure SwiftUI, `#if os(macOS)` where unavoidable).
- **Testing:** Swift Testing unit-test target for the engine, analyzers, parser, and JWT signer.

**Style rules (from CLAUDE.md):** 4-space indent, `@State private var`, no force unwrapping, no Combine (async/await), Swift Testing framework.

---

## 1. Data Models (`Models/`)

### `Severity.swift`
```swift
enum Severity: String, Codable, CaseIterable, Sendable, Comparable {
    case critical, warning, suggestion
}
```
Computed: `displayName`, `systemImage` (exclamationmark.octagon.fill / exclamationmark.triangle.fill / lightbulb.fill), `color` (red/orange/blue), `pointDeduction: Int` (25 / 10 / 3), `estimatedFixMinutes: Int` (30 / 15 / 5), `sortOrder`.

### NEW `Models/AnalysisCategory.swift`
```swift
enum AnalysisCategory: String, Codable, CaseIterable, Sendable {
    case project, metadata, privacy, storeKit, review
}
```
Computed: `displayName` ("Project Configuration", "App Store Metadata", "Privacy", "StoreKit", "Review Readiness"), `systemImage`, `weight: Int` — project 25, privacy 25, review 20, metadata 15, storeKit 15 (sums to 100).

### `Finding.swift`
```swift
struct Finding: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let category: AnalysisCategory
    let severity: Severity
    let title: String            // "Missing camera usage description"
    let detail: String           // what & why it matters for review
    let suggestedFix: String     // concrete action
    let affectedPath: String?    // relative path within project
}
```

### `Project.swift`
```swift
struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let projectFileURL: URL              // .../Foo.xcodeproj
    let directoryURL: URL                // parent folder
    let bundleIdentifier: String?
    let deploymentTargets: [String: String]  // "macosx" -> "27.0"
    let targetNames: [String]
    let appIconImageData: Data?          // first AppIcon png in .xcassets, if any
}
```

### `Report.swift`
```swift
struct Report: Identifiable, Sendable {
    let id: UUID
    let projectName: String
    let bundleIdentifier: String?
    let generatedAt: Date
    let results: [AnalysisResult]
    let overallScore: Int                // 0...100 weighted
    var aiSummary: ReportSummaryText?    // nil while generating
    // Computed: allFindings, criticalCount, warningCount, suggestionCount,
    // estimatedFixTime: Duration (sum of severity minutes)
}

struct ReportSummaryText: Sendable {
    let overview: String
    let topPriorities: [String]
    let isAIGenerated: Bool
}
```

---

## 2. Engine (`Engine/`)

### `AnalysisResult.swift`
```swift
struct AnalysisResult: Sendable {
    let category: AnalysisCategory
    let findings: [Finding]
    let score: Int          // 0...100 for this category
    let checksPerformed: Int
    let wasSkipped: Bool    // e.g. Metadata without ASC credentials
    let skipReason: String?
}
```

### `AnalysisContext.swift`
Built once by `ProjectService`, consumed by all analyzers (no analyzer re-parses the pbxproj). Must be fully `Sendable` — **no `[String: Any]`**; extract typed data at parse time:
```swift
struct AnalysisContext: Sendable {
    let project: Project
    let targets: [TargetInfo]           // name, productType, merged buildSettings [config: [String: String]]
    let infoPlists: [String: InfoPlistData]     // per target; typed wrapper (string/bool values only)
    let entitlements: [String: [String: String]]
    let sourceFileURLs: [URL]           // .swift/.m under project dir
    let resourceFileURLs: [URL]         // PrivacyInfo.xcprivacy, .storekit, plists, etc.
    let ascCredentials: ASCCredentials? // nil => MetadataAnalyzer skips
}
```

### `Analyzer.swift`
```swift
protocol Analyzer: Sendable {
    var category: AnalysisCategory { get }
    func analyze(_ context: AnalysisContext) async -> AnalysisResult
}
```
Analyzers never throw — internal errors become a `warning` Finding ("Could not complete X check") so one failure never kills the run.

### `AnalyzerEngine.swift`
```swift
enum AnalysisProgress: Sendable {
    case started(AnalysisCategory)
    case finished(AnalysisCategory)
}

struct AnalyzerEngine: Sendable {
    let analyzers: [any Analyzer]   // default: all five
    func run(context: AnalysisContext,
             progress: @Sendable @escaping (AnalysisProgress) -> Void) async -> Report
}
```
- Run analyzers **concurrently** with `withTaskGroup` (Metadata's network dominates; locals are ms-fast).
- Progress reaches `AnalysisView` via an `AsyncStream<AnalysisProgress>` created in `AppState.startAnalysis()`. Minimum ~0.6 s per stage display is enforced in the **view**, not the engine.

### Scoring
- Category score = `max(0, 100 - Σ severity.pointDeduction)` over that category's findings.
- Overall = `Σ (categoryScore × weight) / Σ weight`, **excluding skipped categories from both sums** (no ASC credentials ≠ penalty; Results shows "Not checked").
- Estimated fix time = `Σ severity.estimatedFixMinutes` → formatted `Duration` ("~1 hr 25 min").

---

## 3. Services (`Services/`)

### NEW `Services/XcodeProjectParser.swift`
- Parse `project.pbxproj` with `PropertyListSerialization.propertyList(from:options:format:)` — handles both OpenStep and XML variants. **No regex, no third-party libs.**
- Walk `objects`: `rootObject` → `PBXProject` → `targets` (`PBXNativeTarget`) → `buildConfigurationList` → `XCBuildConfiguration.buildSettings` (merge project-level + target-level, target wins). Extract: `PRODUCT_BUNDLE_IDENTIFIER`, `*_DEPLOYMENT_TARGET`, `CODE_SIGN_*`, `DEVELOPMENT_TEAM`, `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_FILE`, `GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_*` (usage descriptions for generated plists live here!), `SUPPORTED_PLATFORMS`, versions.
- File discovery: this project uses **synchronized folder groups** (Xcode 16+), so filesystem enumeration under the project directory is the primary mechanism (skip `.git`, `DerivedData`, `Pods`, `.build`); pbxproj `PBXFileReference`s are supplementary.
- Parse failures are non-fatal: open with degraded info + a warning finding.

### `ProjectService.swift`
- `func openProject(at url: URL) throws -> Project` — caller (AppState) manages `startAccessingSecurityScopedResource()`; keep access alive while project is open, stop on close.
- `func makeContext(for project: Project, credentials: ASCCredentials?) async throws -> AnalysisContext` — loads Info.plists, entitlements, enumerates source/resource files.

### `RecentProjectsService.swift`
- `struct RecentProject: Codable { name, bundleIdentifier, bookmarkData: Data, lastOpened: Date }` — JSON array in UserDefaults key `"recentProjects"`, cap 8, most-recent first.
- Bookmarks: `url.bookmarkData(options: .withSecurityScope)`; resolve with `URL(resolvingBookmarkData:options:.withSecurityScope, bookmarkDataIsStale:)`, re-save if stale. Wrap `.withSecurityScope` in `#if os(macOS)`. Prune dead entries.

### `SettingsService.swift`
`@MainActor @Observable final class SettingsService`:
- `appearance: Appearance` (`enum { system, light, dark }` → `colorScheme`)
- `isAIEnabled: Bool`, `hasCompletedOnboarding: Bool`
- `ascIssuerID: String`, `ascKeyID: String` (UserDefaults); private key in Keychain via `KeychainStore`; `var ascCredentials: ASCCredentials?` assembled when all three present.
- Persist via UserDefaults in `didSet` (no `@AppStorage` inside `@Observable`).

### NEW `Services/AppStoreConnect/` (4 files)
- **`ASCCredentials.swift`** — `struct ASCCredentials: Sendable { let issuerID, keyID, privateKeyPEM: String }`
- **`ASCJWTSigner.swift`** — ES256 JWT via CryptoKit, zero deps:
  - Header `{"alg":"ES256","kid":keyID,"typ":"JWT"}`; payload `{"iss":issuerID,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}` (20-min max lifetime).
  - `P256.Signing.PrivateKey(pemRepresentation:)` accepts the .p8 PEM directly. Sign `base64url(header).base64url(payload)`; use `signature.rawRepresentation` (64-byte r‖s — correct for JWT, **not DER**). Base64url helper: no padding, `-`/`_`.
  - Cache token; re-sign when < 60 s from expiry.
- **`ASCClient.swift`** — minimal URLSession client: `func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T` against `https://api.appstoreconnect.apple.com`, `Authorization: Bearer <jwt>`. Envelope: `ASCResponse<A> { data: [ASCResource<A>] }`, `ASCResource<A> { id, attributes }`. Typed errors: `.unauthorized`, `.appNotFound`, `.rateLimited`, `.network`.
  Endpoints:
  - `GET /v1/apps?filter[bundleId]={bundleID}`
  - `GET /v1/apps/{appID}/appInfos` → `GET /v1/appInfos/{id}/appInfoLocalizations` (`privacyPolicyUrl`, `locale`, `name`, `subtitle`)
  - `GET /v1/apps/{appID}/appStoreVersions?limit=1` → `GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations` (`description`, `keywords`, `supportUrl`, `marketingUrl`, `whatsNew`, `locale`)
- **`KeychainStore.swift`** — Security.framework wrapper (`kSecClassGenericPassword`, service `"com.noahmcclung.DeveloperCompanion.asc"`): `save/load/delete` for the .p8 PEM. No extra entitlement needed for sandboxed generic-password items.

---

## 4. The Five Analyzers (`Engine/Analyzers/`)

**`ProjectAnalyzer.swift`** (weight 25) — per app target: bundle ID present and not placeholder (`com.example.*`, `com.yourcompany.*`) [critical]; marketing version + build number set [warning]; signing configured (`CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM`) [warning]; Release config sane (no `-Onone`/debug flags) [warning]; entitlements file referenced but missing on disk [critical]; unusually old deployment target [suggestion].

**`PrivacyAnalyzer.swift`** (weight 25) —
- Scan sources for framework usage → required usage-description keys: AVFoundation capture → `NSCameraUsageDescription`/`NSMicrophoneUsageDescription`; CoreLocation → `NSLocation*UsageDescription`; Photos, Contacts, EventKit, CoreBluetooth, LocalAuthentication (FaceID), Speech, HealthKit, AppTrackingTransparency → their keys. Check **both** the Info.plist file and `INFOPLIST_KEY_NS...` build settings. Missing = **critical** (auto-reject).
- `PrivacyInfo.xcprivacy`: missing while required-reason APIs detected (`UserDefaults`, file-timestamp APIs, `systemUptime`) = warning; missing entirely = suggestion.

**`StoreKitAnalyzer.swift`** (weight 15) — `wasSkipped` if no `import StoreKit` and no `.storekit` file. Otherwise: product ID literals with no `.storekit` config [suggestion]; IDs in code absent from `.storekit` JSON [warning]; `Product.purchase` without restore path (`AppStore.sync` / `Transaction.currentEntitlements`) [critical — review requirement]; subscriptions missing group/localization [warning].

**`ReviewAnalyzer.swift`** (weight 20) — heuristics over sources + plists: external payment steering (PayPal/Stripe checkout links, "buy on our website" strings) [critical]; `http://` URLs without ATS exception [warning]; placeholder content ("Lorem ipsum", TODO/FIXME in user-facing strings) [warning]; `UIWebView` [critical — hard reject]; weather/data providers (OpenWeather etc.) → attribution reminder [suggestion]; account creation without account-deletion reference [warning]. **Severity discipline: heuristic guesses cap at warning/suggestion; only certain-rejection items are critical.**

**`MetadataAnalyzer.swift`** (weight 15) — requires `ascCredentials`, else skipped with reason "Add App Store Connect credentials in Settings". Resolve app by bundle ID (`appNotFound` → critical "App not found on App Store Connect"). Checks: `privacyPolicyUrl` missing [critical]; `supportUrl` missing [critical]; `marketingUrl` missing [suggestion]; description empty/< 30 chars [warning]; keywords empty [warning]; appInfo localizations missing version localizations [warning]; URLs not https [warning]. No `appStoreVersions` at all → critical "no version created". 401/404/429 → readable findings, never crashes.

---

## 5. AI Layer (`AI/`)

### `AIProvider.swift`
```swift
protocol AIProvider: Sendable {
    var name: String { get }
    func availability() async -> AIAvailability   // .available | .unavailable(reason: String)
    func generateSummary(from input: ReportSummaryInput) async throws -> ReportSummaryText
}
struct ReportSummaryInput: Sendable {
    let projectName: String; let overallScore: Int
    let categoryLines: [String]; let topFindings: [String]   // pre-digested, bounded
}
```

### `AppleIntelligenceProvider.swift`
- `import FoundationModels`. Availability via `SystemLanguageModel.default.availability` (map `.deviceNotEligible` / `.modelNotReady` / other to readable strings).
- Guided generation:
```swift
@Generable
struct GeneratedSummary {
    @Guide(description: "2-3 sentence plain-language assessment of release readiness")
    let overview: String
    @Guide(description: "Up to 3 highest-impact actions, most important first", .maximumCount(3))
    let topPriorities: [String]
}
```
- `LanguageModelSession(instructions:)` — "You explain App Store review-readiness reports. Be concise, factual, encouraging. Never invent findings not in the input." → `try await session.respond(to: prompt, generating: GeneratedSummary.self)`.

### `AIReportGenerator.swift`
- Owns provider + fallback. `func summary(for report: Report, aiEnabled: Bool) async -> ReportSummaryText`.
- Prompt: overall score, one line per category ("Privacy: 60/100, 1 critical, 2 warnings"), top ~8 findings by severity. **Bounded — never dump all findings** (small on-device context).
- Fallback (AI off/unavailable/throws): deterministic template — score band ("Nearly ready" ≥ 85 / "A few blockers" ≥ 60 / "Significant work needed"), counts sentence, top 3 finding titles as priorities, `isAIGenerated: false`. UI shows "Generated without Apple Intelligence" footnote.

---

## 6. App State & Navigation (`App/`)

### `Router.swift`
```swift
enum Route: Hashable { case project, analysis, results }

@MainActor @Observable final class Router {
    var path: [Route] = []
    func showProject() / showAnalysis() / showResults() / popToHome()
}
```
Payloads (`Project`, `Report`) live in AppState, not routes — "Back to Home" = `path.removeAll()`.

### `AppState.swift`
`@MainActor @Observable final class AppState`, injected via `.environment()`:
- Owns: `settings`, `recents`, `projectService`, `reportGenerator`, `router`.
- `var currentProject: Project?`, `var currentReport: Report?`, `var analysisProgress: [AnalysisCategory: StageState]`, alert/error state.
- `func openProject(at url: URL)` — security scope → parse → add recent → `router.showProject()`.
- `func startAnalysis() async` — build context (attach `settings.ascCredentials`), `router.showAnalysis()`, run engine with progress stream, generate AI summary (may complete after arriving on Results — shimmer while pending), set report, `router.showResults()`.

### `DeveloperCompanionApp.swift`
```swift
@main struct DeveloperCompanionApp: App {
    @State private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()   // NavigationStack(path:) { HomeView() } + onboarding sheet
                .environment(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }
        #if os(macOS)
        Settings { SettingsView().environment(appState) }
        #endif
    }
}
```
Onboarding = first-launch sheet on HomeView (interactive dismiss disabled), not a root swap.

---

## 7. Views (`Views/`)

- **`OnboardingView.swift`** — 3 pages (Welcome / How analysis works / Privacy: "analysis is local; ASC optional"), page dots, "Get Started" sets `hasCompletedOnboarding`. Simple index + transition paging (no TabView styling issues on macOS).
- **`HomeView.swift`** — ASC-style "My Projects": prominent "Open Project…" card → `.fileImporter` with `UTType(filenameExtension: "xcodeproj", conformingTo: .package)`; `LazyVGrid` of recent cards (icon, name, bundle ID, last opened; context menu Remove); empty state; toolbar gear → `SettingsLink`.
- **`ProjectView.swift`** — centered icon (fallback `app.dashed`), name, copyable monospaced bundle ID, target/platform chips, big filled **Analyze** button; ASC status line ("Metadata checks enabled" / "Add ASC key in Settings").
- **`AnalysisView.swift`** — back button hidden; checklist of 5 categories (symbol + name + spinner→checkmark) driven by `analysisProgress`; rotating status line ("Reading project.pbxproj…", "Checking privacy manifest…"); thin progress bar; ~0.6 s minimum per stage.
- **`ResultsView.swift`** — scrollable: (1) score ring (`Circle().trim`, angular gradient red→orange→green, animated, big number, fix-time pill); (2) AI summary card (sparkles icon, overview, numbered priorities, shimmer while generating, fallback footnote); (3) category breakdown rows (mini bar, `72/100` or "Not checked" + reason); (4) findings in Critical/Warnings/Suggestions sections, each a `DisclosureGroup` (expanded: detail, "Suggested fix" callout, affected path); (5) "Back to Home".
- **`SettingsView.swift`** — macOS Settings tabs: **General** (appearance), **Intelligence** (AI toggle + live availability line), **App Store Connect** (Issuer ID, Key ID fields; "Import .p8 Key…" fileImporter → Keychain; stored indicator; Remove key), **About** (version, privacy/terms/contact `Link`s).

---

## 8. New Files & Config Changes

| New file | Purpose |
|---|---|
| `Models/AnalysisCategory.swift` | category enum + weights |
| `Services/XcodeProjectParser.swift` | pbxproj → targets/settings/files |
| `Services/AppStoreConnect/ASCCredentials.swift` | credentials model |
| `Services/AppStoreConnect/ASCJWTSigner.swift` | ES256 JWT via CryptoKit |
| `Services/AppStoreConnect/ASCClient.swift` | minimal REST client + DTOs |
| `Services/AppStoreConnect/KeychainStore.swift` | .p8 Keychain storage |
| `Views/RootView.swift` (or inline in app file) | NavigationStack + onboarding gate |
| `Developer CompanionTests/` target | Swift Testing: `EngineTests`, `ScoringTests`, `XcodeProjectParserTests`, per-analyzer tests, `ASCJWTSignerTests`, `Fixtures/` (sample pbxproj, Info.plist, `.storekit`, source snippets) |

**Build config:** add `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (generates `com.apple.security.network.client`, consistent with existing entitlements-via-build-settings). Add unit test target (Swift Testing, `import Testing`).

---

## 9. Build Order

**Phase 1 — Runnable shell.** `DeveloperCompanionApp`, `AppState`, `Router`, all Models, `SettingsService`, `OnboardingView`, `HomeView` (fileImporter wired, empty recents), `ProjectView` (placeholder), `SettingsView` (appearance only).
*Exit:* builds & runs on macOS; onboarding shows once; fileImporter returns a URL.

**Phase 2 — Real project opening.** `XcodeProjectParser`, `ProjectService`, `RecentProjectsService`, `AnalysisContext`; ProjectView shows real data; recents live with bookmarks.
*Exit:* open this very `.xcodeproj`; correct name/bundle ID/targets; quit → relaunch → reopen from recents.

**Phase 3 — Engine + local analyzers + full flow.** `Analyzer`, `AnalyzerEngine`, `AnalysisResult`, `Report`, Project/Privacy/StoreKit/Review analyzers, `AnalysisView`, `ResultsView` (template summary inline).
*Exit:* Analyze → animated loading → scored results end-to-end against this repo + one other project.

**Phase 4 — Tests.** Swift Testing target + fixtures. Cover: parser extraction, each analyzer on fixtures, scoring math (deductions, weights, skipped-category exclusion, clamping), fix-time heuristic, JWT signer (decode segments, verify signature with derived public key — offline).
*Exit:* `RunAllTests` green.

**Phase 5 — App Store Connect.** `KeychainStore`, `ASCCredentials`, `ASCJWTSigner`, `ASCClient`, `MetadataAnalyzer`, ASC settings pane, network entitlement.
*Exit:* with a real key, Metadata populates for a published bundle ID; without credentials, graceful "Not checked"; 401/404 → readable findings.

**Phase 6 — AI summary + polish.** `AIProvider`, `AppleIntelligenceProvider`, `AIReportGenerator`, Results AI card + shimmer, Intelligence pane availability, onboarding copy, empty states, animations.
*Exit:* real generated summary on an Apple Intelligence machine; toggle off → fallback template + footnote.

---

## 10. Verification

- Every phase: `BuildProject` (macOS destination) + `XcodeRefreshCodeIssuesInFile` for fast iteration; `RunProject` smoke test; Previews with `#if DEBUG` mock fixtures (`Report.preview`, `Project.preview`).
- **Dogfood:** this project is the canonical sample — it should flag its own missing `PrivacyInfo.xcprivacy` etc.; sanity-check score plausibility.
- Engine correctness = Phase 4 unit tests; add regression fixtures when analyzers misfire on real projects.
- ASC: JWT verified offline in tests; live path manually with the user's key.
- AI: manual on-device; unit-test prompt builder (bounded, includes top findings) and fallback template (pure functions).

---

## 11. Risks & Gotchas

1. **SDK 27 `@State` macro** — if a view fails with "used before being initialized" / "invalid redeclaration of synthesized property" or ViewBuilder overload ambiguity, consult the `xcode-integration:swiftui-whats-new-27` skill **before** attempting a fix (init-reorder is the wrong fix). Use `xcode-integration:swiftui-specialist` for Observable/ForEach patterns.
2. **Strict concurrency** (`SWIFT_APPROACHABLE_CONCURRENCY = YES`, likely MainActor-default) — services/analyzers doing file I/O must be explicitly `nonisolated`/`Sendable`; `AnalysisContext` stays fully value-typed.
3. **FoundationModels availability on dev machine** — mock provider behind the protocol drives previews/UI if unavailable locally.
4. **pbxproj variability** — synchronized folder groups vs classic references, XML vs OpenStep; settings from pbxproj + files from filesystem covers both; parse failures degrade, never block.
5. **ASC edge cases** — new app record with no version → critical finding; rate limits fine (~5 requests/run); no-ASC accounts → skipped category is the designed path.
6. **Bookmark staleness** — re-resolve, re-save, prune dead recents.
7. **Analyzer false positives** — heuristics cap at warning/suggestion; only certain rejections are critical.
8. **Concurrent agents in workspace** — other sessions ("Create DeveloperCompanion iOS app file structure") may touch the same stubs; check file contents before overwriting.
