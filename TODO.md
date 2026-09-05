# PreFlight — Pre-Launch TODO

**Reference:** PLAN.md is authoritative. If anything here conflicts with it, PLAN.md wins.
**Target:** ~1 month to launch. ~$12.99 one-time, Mac App Store.
**Positioning:** "The most trustworthy pre-submission check for solo/indie Apple developers — built on facts you can verify, not AI guesses."

---

## Current State (verified 2026-08-11)

The core product works end-to-end:
- 7 analyzers running concurrently (Project, Privacy, StoreKit, Review, Metadata, Accessibility, DeviceSupport)
- Full Finding model: confidence (fact/observation), rejection likelihood, guideline refs, evidence, whyItMatters, fix suggestion, fix time — all rendered in ResultsView
- Severity-clamping invariant for heuristic findings (enforced + unit-tested in ModelTests.swift)
- Deep ASC integration: apps, appInfo, versions, EULA, review detail/demo account, subscriptions, screenshots
- Apple Intelligence AI layer (on-device, bounded input, deterministic fallback)
- ManualCheck static checklist for items that can't be automated
- Markdown export (ReportExporter)
- PrivacyInfo.xcprivacy (dogfooded)
- Legal docs exist in-repo (Legal/Privacy Policy.txt, Legal/Terms of Use.txt)

---

## Phase 0 — Strategic Decisions ✅ COMPLETE (2026-08-12)

- [x] **Free-tier boundary:** Project + Privacy + Review pillars fully free. Metadata (ASC) + StoreKit + AI summary + Markdown export require $12.99 unlock. Paywall is implemented as a one-time StoreKit 2 non-subscription purchase.
- [x] **Name:** Keeping "PreFlight" for v1.0. Rename review deferred to Phase 6 post-launch.
- [x] **Distribution:** Mac App Store. Targeting the macOS 27 public release (~September 2026) as the launch window. **This is a hard deadline — macOS 27 ships publicly next month.**
- [ ] **[P1] Trademark check:** Will research separately before any paid marketing spend. Using "PreFlight" in the meantime.

> **macOS 27 launch timing note:** We're aiming to ship alongside or shortly after the macOS 27 public release. This means we can target macOS 27 APIs (FoundationModels updates, SwiftUI 27 changes) and should have the app ready for App Review submission ~1–2 weeks before the OS ships to give Apple time to review.

---

## Phase 1 — MVP Completion (~2 weeks)

### 1A. Tests — Fix the Broken Test Target [P0] ✅ COMPLETE (2026-08-12)

- [x] `PreFlightTests` unit testing bundle target added. All 11 tests across 3 suites pass: `ASCJWTSigner` (3), `Finding invariants` (4), `Scoring` (4 — wait, let me re-count). Target uses `PBXFileSystemSynchronizedRootGroup` + Swift Testing framework. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` set on test target to match main app.
- [ ] **[P0]** Add analyzer fixture tests — one fixture per analyzer proving documented checks actually fire:
  - `ProjectAnalyzer`: catches `com.example.` placeholder bundle ID
  - `ProjectAnalyzer`: catches a missing `NSCameraUsageDescription` when camera usage is present in source
  - `PrivacyAnalyzer`: flags a missing usage string for a detected API
  - `ReviewAnalyzer`: flags `checkout.stripe.com` external payment link
  - `MetadataAnalyzer`: flags missing screenshots for a locale
  - `ReviewAnalyzer`: flags missing demo account credentials
  - `StoreKitAnalyzer`: flags a missing restore-purchases path
  - Include the OneFocus rejection scenario as a canonical regression fixture

### 1B. ASC Privacy Label Cross-Check [P0] ✅ COMPLETE (2026-08-12)

- [x] `KnownDataCollectors.swift` — shared SDK table (11 SDKs: RevenueCat, Firebase Analytics/Crashlytics, Amplitude, Mixpanel, Sentry, Segment, AppsFlyer, Adjust, Intercom, PostHog)
- [x] `PrivacyAnalyzer` — parses `PrivacyInfo.xcprivacy` and cross-references detected SDKs against declared `NSPrivacyCollectedDataType` entries (local, always runs, no ASC needed)
- [x] `MetadataAnalyzer` — `privacyLabelFindings()` calls ASC `appPrivacyDeclarations` endpoint; cross-references detected SDKs against declared ASC categories; `try?` throughout so a 404 or schema mismatch degrades to an empty result, no false positives
- [x] `ASCClient` — `AppPrivacyDeclarationAttributes` + `appPrivacyDeclarations(forAppID:)` endpoint

- [ ] **[P0]** Add App Privacy ("nutrition label") check to `MetadataAnalyzer`:
  - Fetch the app's declared data-collection categories from the ASC app-privacy-declarations endpoint
  - Cross-reference against source-detected SDK/API usage patterns already scanned by `PrivacyAnalyzer` (usage strings, framework imports)
  - Surface a `Finding` when a known data-collecting SDK is present but the corresponding privacy declaration is absent
  - Tag as `.fact` / `.critical` if the SDK is definitively a known data collector, `.observation` / `.warning` if heuristic

### 1C. IAP & Free Tier [P0] ✅ COMPLETE (2026-08-14)

- [x] **[P0]** `PurchaseService` — `@MainActor @Observable`, StoreKit 2 `Product` + `Transaction.currentEntitlements`. Never stores purchase state in UserDefaults; always verified transactionally. Product ID: `com.noahmcclung.PreFlight.unlock`.
- [x] **[P0]** Free-tier split in `AppState.startAnalysis()` — paid analyzers (Metadata, StoreKit) only added to engine when `purchases.isPurchased`. AI summary also gated.
- [x] **[P0]** `PaywallView` — sheet shown when locked feature is tapped. Shows 4 unlocked features, localized price from StoreKit (falls back to "$12.99"), purchase + restore buttons, loading state, error display. Auto-dismisses on purchase.
- [x] **[P0]** `ResultsView` — locked category rows in the breakdown, locked AI summary card, "Copy Checklist" toolbar button shows lock icon and triggers paywall for free users.
- [x] **[P0]** Transaction listener in `PreFlightApp.task` — `for await result in Transaction.updates` loop runs for app lifetime; handles background transactions (refunds, cross-device).
- [x] **[P0]** `AnalysisCategory.requiresPurchase` — `.metadata` and `.storeKit` return `true`; used by both engine gating and UI locked-row logic.
- [x] **[P0]** `PurchaseService.displayPrice` — computed property isolates StoreKit type from views.
- [ ] **[P1]** Add one-time IAP product checks for non-subscription IAP to `MetadataAnalyzer` (currently only subscription groups are checked; standalone IAP products aren't cross-referenced)
- [ ] **[P1]** Register product ID `com.noahmcclung.PreFlight.unlock` in App Store Connect before submission

### 1D. Analysis History [P0] ✅ COMPLETE (2026-08-22)

- [x] **[P0]** `ReportStore` refactored to retain last 10 timestamped reports per project — each run stored as `<uuid>.json` in a per-project subdirectory; pruned to 10 by modification date; AI summary re-save reuses same UUID, no duplicates
- [x] **[P0]** Score delta badge in `ProjectView` — compares `reportHistory[0]` vs `reportHistory[1]`, shows "+N pts vs Aug DD" or "No change"
- [x] **[P1]** Last 5 runs list in `ProjectView` — date + color-coded score in a glass card

### 1E. Deepen Experience Pillar Analyzers [P0] ✅ COMPLETE (2026-08-22)

- [x] **[P0]** `AccessibilityAnalyzer` — 6 checks total (up from 2):
  - Fixed-size font / Dynamic Type check (existing)
  - Icon-only buttons without accessibilityLabel (existing)
  - Custom UIControl/NSControl/UIView/NSView subclass without accessibilityTraits (new)
  - TextField without keyboardType (new)
  - Animations without accessibilityReduceMotion (new)
  - Interactive controls with frame dimensions below 44pt without contentShape compensation (new)
- [x] **[P0]** `DeviceSupportAnalyzer` — doc comment scoped to "iPad multitasking + Mac Catalyst"; added Mac Catalyst check (flags `SUPPORTS_MACCATALYST = YES` without targetEnvironment, UIUserInterfaceIdiom.mac, sizeRestrictions, or NSApplication); does NOT claim visionOS coverage
- [ ] **[P1]** Add build-upload verification to `MetadataAnalyzer` — check whether a processed build actually exists for the current app version in ASC (currently never verified)

### 1F. Trust-Building Primitives [P1] ✅ COMPLETE (2026-08-22)

- [x] **[P1]** Methodology tab in Settings — 5 sections: How Findings Are Generated, Facts vs. Heuristics, Severity Clamping, What PreFlight Checks, What PreFlight Cannot Check; Settings window resized to 500×460
- [x] **[P1]** Developer section in Settings > General — "Simulate Pro Unlock" toggle (UserDefaults-backed `devOverrideEnabled`, bypasses StoreKit without a real transaction)
- [x] **[P1]** Ruleset stamp in `ResultsView` scoreHeader: "Checked against App Store Review Guidelines · August 2026"

---

## Phase 2 — Validation (~3–4 days, overlapping Phase 1)

This is critical. The entire pitch is "trust our findings" — that must be tested against reality before launch.

- [ ] **[P0]** Dogfood PreFlight against 3–5 real Xcode projects, including at least one with a known past App Store rejection. Confirm findings match the actual rejection cause. Document every mismatch.
- [ ] **[P0]** Recruit 3–5 external indie developers for private beta. Explicitly capture false positives — every confirmed false positive is a P0 bug. "A virtual reviewer that cries wolf loses all credibility."
- [ ] **[P0]** Run PreFlight's own `MetadataAnalyzer` against PreFlight's own ASC record (dogfooding the analyzer itself)
- [ ] **[P1]** Run the same test project through Cleared's and Appoval's free tiers. Compare findings — confirm PreFlight doesn't miss something a free competitor catches trivially (especially the privacy-label mismatch case)

---

## Phase 3 — Polish (~1 week)

### 3A. App Icon

- [x] **[P1]** Confirm the `AppIcon.icon` asset (Icon Composer bundle, currently untracked in git) is correctly wired into build settings as the shipping app icon. Verify it renders at all required sizes.

### 3B. Onboarding

- [ ] **[P1]** Copy pass on `OnboardingView` to reflect narrowed positioning:
  - Lead with trust/evidence framing ("facts you can verify, not AI guesses"), not "AI-powered"
  - Target: solo/indie Apple-native developer who ships occasionally
  - Remove or demote any "first mover" or uniqueness claims not supported by the competitive landscape
  - Ensure free-tier capabilities are clearly explained before any paywall encounter

### 3C. Error & Empty States

- [ ] **[P1]** Audit and fix each empty/error state — confirm graceful degradation for:
  - No ASC key configured (no Metadata or StoreKit results, but rest of analysis proceeds)
  - ASC 401 (invalid credentials — clear error, not crash)
  - ASC 404 (app not found — clear error)
  - ASC 429 (rate limit — back-off message, partial results shown)
  - Project with zero findings (positive state — "No issues detected in X categories")
  - `.pbxproj` parse failure (clear error, offer to retry without project-level checks)
  - Apple Intelligence not available (deterministic fallback template used — confirm this is surfaced clearly in UI)

### 3D. ResultsView Polish

- [ ] **[P2]** Visual pass on `ResultsView` finding cards:
  - Evidence, guideline reference, and confidence badges are the actual trust surface — make them scannable at a glance, not buried in a DisclosureGroup
  - Ensure `.fact` vs `.observation` label is visually distinct and immediately readable
  - Consider making rejection likelihood a visual indicator (not just text) for quick triage

---

## Phase 4 — Distribution Readiness (~3–5 days)

### 4A. App Store Connect Setup

- [ ] **[P0]** Finalize the ASC record: app name, subtitle, category (Developer Tools), pricing ($12.99 one-time)
- [ ] **[P0]** Confirm the free-tier IAP product is set up in ASC in an App-Review-compliant way (in-app unlock, not a separate free/paid app split)
- [ ] **[P0]** Confirm `Legal/Privacy Policy.txt` and `Legal/Terms of Use.txt` are hosted at stable public URLs and linked correctly from `SettingsView`'s About tab

### 4B. App Store Listing

- [ ] **[P1]** Write App Store description:
  - Lead with the honest differentiator (evidence/guideline-reference discipline, deepest ASC integration in the category)
  - Don't claim to be first or unique-in-category — "most trustworthy" is supportable, "first" is not
  - Explain the free tier clearly
- [ ] **[P1]** Create App Store screenshots (minimum 3, ideally 5) for Mac:
  - Show the Results view with real findings, evidence, and guideline references visible
  - Show the ASC integration working (live data)
  - Show the AI summary (clearly labeled as a summary, not findings source)
  - Run PreFlight's own MetadataAnalyzer against its own listing before submitting
- [ ] **[P1]** Keywords strategy — given name collisions (getpreflight.app, preflight.build, Oxbit Preflight), choose a keyword set that differentiates in search:
  - Prioritize "App Store review," "Xcode," "App Review rejection," "App Store Connect," "app submission"
  - Avoid "preflight" as a keyword (collisions, low marginal value)
- [ ] **[P1]** Write App Preview (optional but recommended) — 15–30s screen recording of an analysis run

---

## Phase 5 — Launch (~1–2 days + ongoing)

- [ ] **[P1]** Prepare a Show HN post:
  - Be candid that the category is new and has competition
  - Lead with the technical architecture (fact/observation model, guideline refs, ASC integration depth)
  - Avoid "AI-powered" as the headline claim
- [ ] **[P1]** Prepare a Product Hunt launch:
  - Same framing as HN — trust-first, honest about the category
  - Tagline: "The most trustworthy App Store pre-submission check — facts, not AI guesses"
- [ ] **[P2]** Direct outreach to indie-dev communities:
  - r/iOSProgramming, Swift Forums (/dev/world subforum), iOS Dev Weekly, Indie Dev Monday
  - Lead with a concrete "we caught X that would have gotten you rejected" story from the dogfooding (Phase 2)
  - Do NOT lead with AI framing — observed community skepticism toward generic AI claims is high

---

## Phase 6 — Post-Launch (Ongoing)

- [ ] **[P1]** Add opt-in false-positive reporting: in-app "Mark as not an issue" on any finding, with anonymous signal sent (privacy-respecting). Build toward a published false-positive rate.
- [ ] **[P1]** Revisit CI/CD integration once there's evidence of repeat/recurring usage patterns
- [ ] **[P2]** Revisit rename/branding decision — if name collisions are causing App Store search rank issues or support confusion, a rename is warranted. Not before.
- [ ] **[P2]** Monitor Cleared, Appoval, and Greenlight for major updates — especially if Cleared adds a GUI, Appoval ships ASC integration, or Greenlight adds native Mac packaging

---

## Out of Scope — Do Not Build Before v1.0

These are explicitly deferred, regardless of how good they sound:

- ❌ Agentic auto-fix / code-writing (Oxbit Preflight already does this; not core to trust thesis)
- ❌ Full Run Review / simulator-driven sessions (Greenlight is already there, free; revisit post-1.0)
- ❌ Cross-platform (React Native / Flutter) analysis
- ❌ Hosted CI/CD product with PR comments
- ❌ Multi-AI-provider / bring-your-own-key support
- ❌ Multi-seat / team pricing
- ❌ Full brand rename (Phase 6, post-launch)
- ❌ PDF export (nice to have, not a launch blocker)

---

## Rough Launch Sequencing

```
Week 1:  Phase 0 decisions + 1A (test target) + 1D (ReportStore history) + start 1C (IAP skeleton)
Week 2:  1B (privacy label check) + 1C (IAP complete) + 1E (deepen analyzers) + 1F (trust primitives)
Week 3:  Phase 2 (dogfooding + beta) + Phase 3 (polish, icon, onboarding, error states)
Week 4:  Phase 4 (ASC record, listing, screenshots) + Phase 5 (launch posts) + submit to App Review
```

---

## Completed Work (from earlier sessions)

- [x] Three-pillar model (Configuration / Experience / Compliance)
- [x] Finding model with confidence, rejection likelihood, guideline ref, evidence, whyItMatters, suggested fix, fix time
- [x] Severity-clamping invariant (heuristic observations can never show as certain rejections)
- [x] 7 analyzers: Project, Privacy, StoreKit, Review, Metadata, Accessibility, DeviceSupport
- [x] ASC integration: apps, appInfos, versions, EULA, review detail/demo account, subscriptions, screenshots
- [x] ES256 JWT signing via CryptoKit, Keychain-backed credential storage
- [x] Apple Intelligence AI layer (on-device, bounded, pre-digested, with deterministic fallback)
- [x] ManualCheck static checklist (Paid Apps Agreement, consent before upload, etc.)
- [x] Markdown export (findings as checkboxed list grouped by severity, with guideline refs)
- [x] PrivacyInfo.xcprivacy (dogfooded, accurate)
- [x] Legal docs in-repo (Privacy Policy, Terms of Use)
- [x] Three test files written (ASCJWTSignerTests, ModelTests, ScoringTests) — need target wiring
- [x] Saved-report migration polish (stale/undecodable reports deleted on load)
- [x] Score & coverage framing (Not Verified card, coverage caption, AI summary never claims readiness)
