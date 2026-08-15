# PreFlight — Vision

PreFlight is not a project scanner, a linter, or another AI coding tool.

**PreFlight is a virtual App Review engineer.**

It should be the final step every Apple developer performs before pressing
"Submit for Review." Instead of asking *"are these files configured
correctly?"*, PreFlight answers:

> "If Apple reviewed this app today, what would they likely reject or question?"

Every analyzer, report, design decision, and future feature must support that
framing. PreFlight thinks in terms of App Review, not in terms of project
analyzers.

---

## Three Pillars

Analysis is organized around **how Apple evaluates apps**, not around file
types.

### 1. Configuration — deterministic technical checks

Build settings, bundle configuration, privacy manifest, Info.plist, StoreKit,
App Store Connect metadata, required URLs, assets, localization, deployment
targets.

### 2. Experience — the quality of the application itself

Navigation, accessibility (Dynamic Type, VoiceOver), onboarding, device
support (iPad layouts, macOS resizing), Human Interface Guidelines,
performance, subscription and paywall UX.

These analyzers ask: *does this behave like a polished Apple application?*

### 3. Compliance — think like an App Review engineer

Common rejection patterns, Restore Purchases, subscription disclosures, terms,
privacy policy, support URL, reviewer information, demo account requirements,
external payment references, permission timing, login requirements, broken
links, first-launch experience.

These analyzers answer *"what would Apple likely flag?"* — not *"what
configuration is missing?"*

---

## Finding quality bar

Every issue should read like feedback from an App Review engineer, not a
compiler diagnostic. A finding supports:

- **Severity**
- **Rejection likelihood** — distinct from severity; how likely this is to
  actually impact App Review
- **Confidence** — a deterministic **fact** or a heuristic **observation**
- **Guideline reference** — e.g. "Guideline 3.1.1" where applicable
- **Why this matters** — in App Review terms.
  Not "Privacy Policy URL missing" but "This is a common App Review blocker
  because users must be able to access a Privacy Policy before downloading or
  using subscription-based applications."
- **Evidence** — what the analyzer actually observed
- **Suggested fix** and **estimated fix time**

### Facts vs. observations

**Deterministic analyzers report facts. Heuristic analyzers report
observations. Heuristics are never presented as guaranteed App Review
failures.** Observations cap at warning severity and can never claim certain
rejection. A virtual reviewer that cries wolf loses all credibility.

---

## Run Review (future milestone — explicitly not being built yet)

Simulate an App Review session against the actual running app: launch →
navigate → test onboarding → check permission prompts → verify purchase flow →
restore purchases → verify privacy policy / terms / external links → resize /
rotate → background/foreground → generate a review report.

**Architectural fork (decide before building it):** driving an arbitrary user
app requires `xcodebuild` + `simctl` + an XCUITest-style runner
(`XCUIApplication(bundleIdentifier:)` on a simulator) — none of which a
sandboxed Mac App Store app can invoke. Options:

1. Distribute PreFlight outside MAS (Developer ID, no sandbox) — full capability.
2. Keep the MAS app sandboxed + ship a separate helper CLI that does the driving.
3. Stay sandboxed and only analyze user-supplied artifacts (.xcresult,
   screenshots) — cannot deliver the full vision; fallback only.

Static analysis work is unaffected by this decision.

---

## Apple Intelligence

AI must **never invent issues**. It receives structured analyzer output only.

Responsibilities: prioritize findings, explain issues, identify patterns
across findings, estimate release readiness, generate natural-language
summaries, suggest logical next steps.

It should behave like an experienced App Review engineer — not a coding
assistant. The reviewer *knowledge* (guideline references, rejection
likelihoods, rationale copy) lives in analyzer data, not in the model; the
model arranges and explains it — and it must phrase observations as
possibilities, never verdicts. Inputs stay pre-digested and bounded for the
on-device context window.

---

## Roadmap

**Phase A — Reframe the model.** Introduce the three pillars over the existing
categories. Extend `Finding` with rejection likelihood, confidence,
guideline reference, why-this-matters, and evidence. Rewrite existing finding
copy to the quality bar above.

**Phase B — Deepen deterministic coverage.** Expand ASC integration:
`appStoreReviewDetails` (demo account, reviewer notes — "login-required app
with no demo account" is a top real-world rejection and fully deterministic),
screenshots per locale, subscription groups + localizations, app privacy
details. Asset and localization-completeness checks.

**Phase C — Static Experience/Compliance heuristics.** Source-level
accessibility checks (hardcoded font sizes, image-only buttons without
labels), permission request timing, paywall disclosure proximity,
restore-purchases paths, broken link detection.

**Phase D — Run Review.** Decide the distribution fork, then build the
simulator-driving runner and the session report.
