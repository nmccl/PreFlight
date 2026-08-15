# PreFlight — Product Strategy & Execution Plan

**Last updated:** 2026-08-11
**Status:** Strategic reassessment complete. ~1 month to launch. This document is authoritative — if TODO.md or old planning docs disagree with this file, this file wins.

This replaces the original pre-rename "Developer Companion MVP Implementation Plan." That plan is done — the engine, analyzers, ASC client, AI layer, and UI it described are built and working (see §4). VISION.md remains the qualitative north star for *how PreFlight should think*; this document is the *what and when*, updated after a full competitive research pass.

---

## 0. The decision, up front

We researched the competitive landscape (9 named competitors + broad market scan, ~15 real or attempted products found total) and audited the actual codebase state. The short version:

- **The category is real but crowded and unproven.** App Review rejection is a genuine, chronic developer pain point. At least a dozen builders have independently converged on the same product shape (scan project/build/metadata → map to guidelines → score → suggest fixes) in the last 6–12 months. Almost none of them show real commercial traction yet.
- **PreFlight is not the most differentiated entrant.** A competitor called **Cleared** (native macOS, local-first, one-time price, open-source core) already ships a sharper version of our core thesis, including a specific mismatch-detection feature (SDK-declared vs. developer-declared privacy data) we don't have. An open-source CLI called **Greenlight** (2.4k GitHub stars) already does cloud-based runtime verification of exactly the flows we were planning to use "Run Review" to differentiate on (Restore Purchases, account deletion, Sign in with Apple).
- **PreFlight does have real, shipped, verifiable advantages**: the deepest App Store Connect integration found in the entire survey (review detail/demo account, subscriptions, screenshots — not just basic metadata), a more disciplined Finding trust model (deterministic fact vs. heuristic observation, with enforced severity clamping) than anything else found, and genuine native-macOS polish.
- **Recommendation: B + D — keep the core, reposition, narrow.** Do not rebuild. Do not chase Run Review now (someone else is already there, faster, for free). Do not expand to cross-platform or CI/CD to compete with Appoval/Cleared on breadth. Instead: hold the current architecture, hardennot the trust primitives that are already our best asset, close the one gap that materially matters (ASC privacy-label cross-check), add a free entry point (every real competitor has one; we don't), and narrow positioning to a specific underserved buyer: **the solo/indie Apple-native developer who ships occasionally and wants one trustworthy, low-friction check** — not the CI-embedded/team/cross-platform buyer that Appoval, Cleared's CI story, and Greenlight are already chasing.
- **Kill (E) is wrong** — there's a real, working, honestly-differentiated product here and killing it wastes a month of sound, non-throwaway engineering in a validated (if crowded) category.
- **Full pivot (C) is wrong** — nothing in the research demands abandoning the deterministic-analyzer + fact/observation Finding model + bounded-AI architecture. It's the right shape; competitors validate the shape, they just execute pieces of it better in places.

---

## 1. Why PreFlight exists (revised, honest version)

The original framing — "PreFlight is a virtual App Review engineer" — still holds as a design philosophy (see VISION.md, unchanged). What's changed is the claim underneath it. We are **not** first, **not** uniquely native, and **not** the only one treating AI as an interpreter of structured evidence rather than a source of truth (Cleared does this too, independently).

What PreFlight can honestly claim today, verified against the shipped code:

1. **The most disciplined trust architecture found in the category.** Every `Finding` carries `confidence` (`.fact`/`.observation`), and the model *enforces* that heuristic observations can never present as certain rejections — `Finding.init` clamps `.critical` → `.warning` and `.certain` → `.likely` when confidence is `.observation`. This is a real, tested (`ModelTests.swift`) invariant, not marketing copy. No competitor found publishes anything this specific.
2. **The deepest App Store Connect integration found anywhere in the survey**, including endpoints most competitors don't touch at all: `appStoreReviewDetail` (demo account / reviewer notes — a top real-world rejection cause), subscription groups + localizations, and per-locale screenshot sets.
3. **A coherent mental model** (Configuration / Experience / Compliance pillars) tied to how Apple actually evaluates apps, not to file types.
4. **Native macOS execution quality** — but this is table stakes now, not a differentiator. Cleared, Oxbit Preflight, and App Store Scanner are all also native macOS apps in this exact category.

None of these is individually a moat. Cleared could add severity-clamping in a weekend. Appoval already lists ASC integration as a roadmap item. The honest strategic position is: **this is a "compete on depth and trust within a validated-but-crowded category" situation**, not a blue-ocean situation. The plan below is built on that premise.

---

## 2. Competitive landscape

### 2.1 Matrix (most load-bearing competitors)

| Competitor | Platform | Input | ASC integration | Cross-checking | Coverage | Evidence & fix guidance | AI (where it runs) | Runtime / review simulation | History | Local vs. cloud | Integrations | Pricing | Main strength | Main weakness |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **PreFlight (us)** | Native macOS | Xcode project + optional ASC | Yes — apps, appInfos, versions, EULA, review detail, subscriptions, screenshots | Source↔plist (usage strings), StoreKit code↔`.storekit` config | Privacy, StoreKit, metadata, review heuristics, accessibility, device support | Yes — evidence field, guideline ref, confidence, rejection likelihood, all rendered | On-device Apple Intelligence, bounded/pre-digested input, fallback template | None | **Single snapshot per project — no real history today** | Fully local; AI on-device | None | $12.99 one-time, **no free tier today** | Deepest ASC coverage found; disciplined fact/observation trust model | No free entry point; no history; Accessibility/DeviceSupport analyzers shallow; no privacy-label mismatch check |
| **Cleared** (cleared.sakaax.com) | Native macOS + OSS CLI (`cleared-cli`) | `.ipa`/`.xcarchive` + ASC (read-only) | Yes — privacy labels, basic metadata | **SDK-declared vs. developer-declared privacy data** (e.g. catches RevenueCat undeclared collection) | Privacy manifest, usage strings, ATT, metadata/paywall consistency | Yes — deterministic, specific | Optional only, for explaining findings — on-device (macOS 26+) or user's own Claude/OpenAI/Gemini key; never a source of findings | None (never executes the binary) | Not confirmed | 100% local, no telemetry, no account | **CI/CD via `cleared-cli`** | €15 (Solo) / €25 (Studio), one-time, 3-day trial, **OSS core is free** | Sharp, specific, verifiable privacy-mismatch feature; open-source trust story; CI story | Very low traction (single-digit GitHub stars, no reviews found); ASC coverage narrower than ours |
| **Appoval** (appoval.app) | Web (browser upload) | Source (iOS/RN/Flutter), not binaries | **No** (roadmap item) | Code vs. guideline, not built-vs-declared | "200+ guidelines" (unverified specifics); permissions, privacy strings, private APIs | Yes — file-level references | "Multi-agent AI engine," vendor undisclosed, cloud | None | Yes — 30-day report retention | Client-side zip, server-side scan | **GitHub OAuth, scans on push/PR** | Free static scan; $9.99–$49.99/mo | Real traction (140 PH upvotes, testimonial); GitHub CI integration; cross-platform | Subscription pricing; no ASC integration yet; web-only, not native |
| **Greenlight** (RevylAI, OSS) | CLI (macOS/Linux/CI) | Source, manifests, binaries, ASC metadata | Yes | Not confirmed in depth | Privacy manifests, Android manifests/Gradle too | Yes | Claude Code plugin for AI-assisted fixing | **Yes — cloud runtime verification: account deletion, Restore Purchases, Sign in with Apple flows** | Not confirmed | Free/offline core; cloud for runtime checks | Claude Code plugin, CI-friendly | **Free, open source** | **2.4k GitHub stars — most traction found in this entire survey**; already does runtime verification we were treating as future differentiation | Not Apple-native-focused; no polished GUI; less structured trust model (fact/observation) than ours |
| **Oxbit Preflight** (Mac App Store) | Native macOS | Xcode/Swift source | Not confirmed | Sandbox/privacy/entitlements vs. Info.plist | Sandbox violations, privacy leaks, hardcoded strings | Yes | Local CoreML, hybrid with pattern matching | None | Not confirmed | Local | None found | Free + ~$12 lifetime Pro | **"Smart Auto-Fix" code suggestions** (agentic, we don't do this); direct App Store presence in our exact category | Small, low visibility; scope narrower than ours |
| **App Store Scanner** | Native macOS | .xcodeproj/.xcworkspace/.app/.ipa | No | Not confirmed | Info.plist, PrivacyInfo.xcprivacy, ATS, export compliance, frameworks, hardcoded keys | Risk score, not confirmed evidence-level | None mentioned | None | Not confirmed | Local | None found | Free (5 scans/day) + $5.99 lifetime | Cheapest paid entry found; genuine free tier | No AI, no ASC, shallower checks |
| **getpreflight.app** | Unclear (waitlist) | Xcode project | Claimed "ASC Metadata" check, unclear if live API | Not confirmed | "18+ check categories" | Claimed "fix in code editor," unverified | **None mentioned** | None | Not confirmed | Not confirmed | None found | $24.99 one-time (early-access price) | **Direct name collision**; identical one-time pricing model and positioning to ours | **Pre-launch, zero traction, unverifiable claims** — not a real competitor yet, just a name risk |
| **preflight.build** | Web SPA + claimed GitHub App | Code, metadata, **screenshots** | Claimed, not confirmed live | Not confirmed | Broadest claimed input surface (code + metadata + screenshots) | "AI coding prompts" output — assistive, not agentic | "AI agents," vendor undisclosed, cloud | None | Not confirmed | Cloud | Claimed GitHub App — **the linked App page 404s**, i.e. likely not actually shipped | $17.99–$59.99/mo + $1/scan CI add-on | Broadest claimed scope; live and polished marketing site | **Direct name collision**; marketing outpaces shipped product (broken integration link); zero independent traction; most expensive option found |
| **AppReviewer Preflight** (App Store) | Native iOS | None — static checklist | No | No | Curated guideline checklist, filterable by app type | No (no analysis, just checklist) | None | No | Local | None | Free + ad-removal IAP | Simple, cheap, real App Store listing | **Not a code/project analyzer at all** — not a functional competitor, just a name-adjacent product |

### 2.2 Confirmed non-existent or vaporware (do not plan around these as real threats)

- **AuditStore** — no evidence found anywhere (own site, GitHub, App Store, social, Product Hunt). Treat as non-existent.
- **ShipReady** — the name belongs to an unrelated Shopify boilerplate product. Not a competitor.
- **StorePreflight** — no evidence found. Treat as non-existent.
- **PreReviews** (exact spelling) — no exact match; closest is **PreReview** (prereview.app), itself pre-launch/waitlist with zero independent traction.
- **Vera** (tryvera.sh) — a landing page with a waitlist and a "$10 reserve" deposit, no working product, no disclosed AI model, zero independent mentions anywhere. `vera.sh` doesn't resolve. Treat as vaporware, not a competitor, until it ships.

### 2.3 Other name collisions / adjacent uses of "preflight" worth tracking

- **trypreflight.io** — different space entirely (waitlist-management tool for indie builders), but same wordmark.
- **Oxbit Preflight** — same category, already live on the Mac App Store, direct listing-adjacency risk if we also distribute there.
- Multiple free/OSS **Claude Code / Cursor "skill" tools** use "preflight" in their repo names (e.g. `app-store-preflight-skills`) and do overlapping work, including one that reportedly drives the iOS Simulator via computer use — i.e., a rudimentary free version of "Run Review" already exists in the open-source ecosystem under a name close to ours.

### 2.4 Market read

- Real, chronic developer pain (Guideline 2.1 completeness issues cited as ~40% of rejections; demo-account failures and metadata issues recur constantly in forum threads) — but the loudest public "unfair rejection" stories are frequently wrong on the facts (see the Daring Fireball retraction case found in research), which cuts against any tool promising to predict subjective reviewer judgment calls. Stick to what's mechanically checkable.
- "Just ask an AI chatbot" is a real substitute developers reach for, but the market itself has already concluded raw chat isn't enough — at least five independent Claude Code/Cursor skills exist specifically to add structured scanning underneath an LLM. This validates our "AI interprets structured evidence, never invents findings" architecture as directionally correct — it just means we're one of several implementations of that idea, not the only one.
- Apple's own tooling (Xcode static analyzer, Resolve Center, privacy report generation) is reactive/post-hoc, not a unified pre-submission score — not a direct threat, and the 2026 compliance wave (privacy manifest mandate, 64-bit enforcement) is if anything a tailwind for third-party tools.
- The single biggest structural threat to a **paid** app in this category is the free/OSS cluster (Greenlight, multiple Claude Code skills, Cleared's free core) — free tools that live inside an editor developers already have open. A $12.99 app with zero free entry point is competing against multiple $0 options with real GitHub traction.

---

## 3. Customer questions — honest answers

**"Why PreFlight instead of Vera?"** — Not a real question today; Vera hasn't shipped a working product. Revisit if/when it does.

**"Why PreFlight instead of Cleared?"** — The hardest one. Today: PreFlight's ASC integration is deeper (review detail/demo account, subscriptions, screenshots vs. Cleared's privacy label + basic metadata), and PreFlight's StoreKit-specific analysis (restore-path detection, paywall completeness) is more developed. Cleared's answer is sharper on one specific, credible axis (privacy-declaration mismatch) and it's open-source at the core, which is a real trust signal we don't have. **This is a close, honest fight, not a clear win** — closing the privacy-label gap (§7, Phase 1) is the single highest-leverage move against this specific competitor. However, Cleared doesnt give an overall score, the report is also kidna messy. I also noticed it doesnt look on app store connect. It also requires YOUR own API key, meaning a user needs to have one or buy one. Mine utizlizes CoreAI, meaning theres no need for any of that. That was the whole goal, jump onto these new dev tools before anyone else does, nobody has implemented CoreAI into an app like this yet, I will be one of the first. Another thing it says theres 0 blockers and 1 warning and only gives me two warnings about privacy. Mine gave a detailed report with 17 detailed warnings, why this matters, a suggested fix, etc, it gave suggestions to even further prevent app store rejection. So my hope for this app has went up by qutie a bit, yes we have competitors, but they dont have a lot of users (if any) and theres nothing wrong with solving the same problem. We just need to solve it better, market it better, and build users trust.

**"Why PreFlight instead of AuditStore?"** — Moot; it doesn't appear to exist.

**"Why should I spend $12.99 when another tool is free/cheaper?"** — We cannot honestly answer this yet. Cleared's engine is free/OSS at the core, Appoval has a free static scan, App Store Scanner has 5 free scans/day, and multiple Claude Code skills are entirely free. Until PreFlight has a free entry point and a specific hard-to-replicate capability, "$12.99 for something free elsewhere does 80% of" is a real objection, not a strawman. PreFlight seems to be the cheapest so far.

**"Why shouldn't I just use Claude?"** — Decent, evidence-backed answer *for the category*: raw chat doesn't deterministically parse your project, doesn't cite guideline sections, doesn't produce evidence, and the market itself has already built structured scanners under LLMs because bare chat wasn't enough. This is **not**, however, a good answer for PreFlight *specifically* versus the free Claude Code skills already doing exactly that pattern — that comparison has to be won on depth and polish, not architecture.

**"Why shouldn't I build this myself?"** — Time cost, ASC JWT/API plumbing (genuinely fiddly to get right), guideline currency, and evidence-model discipline. Reasonably strong for developers who don't want to spend a weekend on infrastructure — but weaker for exactly the audience most likely to buy an indie dev tool, since that audience is precisely the one already forking the free GitHub skills.

**"What would make me trust PreFlight's results?"** — The fact/observation clamping, guideline citations, and evidence display are real and shipped. What's missing: a public "how we know this" methodology explainer, a versioned/dated ruleset stamp, and eventually a published false-positive rate. All added to Phase 1/6 below.

**"What would make me open PreFlight every time I ship?"** — Honestly: nothing today. There's no history, no CI hook, and no trend view — it's a one-shot tool, not a ritual. Fixing `ReportStore` to retain history is the cheapest lever here (Phase 1).

**"What would make me switch from another tool to PreFlight?"** — A clear, demoable edge in ASC depth + evidence discipline + polish, or shipping the privacy-mismatch check as well as or better than Cleared does.

**"What would make me tell another developer about it?"** — Catching one real, concrete, would-have-been-rejected issue with clear evidence — the same story every competitor is chasing. No unique answer here except execution quality; don't manufacture one.

---

## 4. Current state of the codebase (verified by direct audit, 2026-08-11)

**Genuinely done, not just "mostly done":**
- Three-pillar model (`Pillar`: Configuration/Experience/Compliance, derived from 7 `AnalysisCategory` cases) — `Models/AnalysisCategory.swift`.
- `Finding` model with confidence, rejection likelihood, guideline reference, evidence, whyItMatters, suggested fix, per-finding fix time — all populated by analyzers and all rendered in `ResultsView`'s `FindingRow` (not dead struct fields).
- Severity-clamping invariant for heuristic findings, enforced in `Finding.init` and unit-tested.
- 7 analyzers running concurrently via `AnalyzerEngine` (`withTaskGroup`): Project (~8 checks), Privacy (~12 checks), StoreKit (~7 checks, skips gracefully with no StoreKit usage), Review (~8 heuristic checks), Metadata (~14 checks against live ASC data), Accessibility (2 checks — shallow), DeviceSupport (2 checks, iPad-only despite the generic name — shallow).
- ASC integration: apps, appInfos/localizations, appStoreVersions/localizations, EULA, `appStoreReviewDetail` (demo account), subscription groups + subscriptions, screenshot sets. ES256 JWT signing via CryptoKit, Keychain-backed credential storage, graceful per-endpoint degradation on partial API scopes.
- AI layer: on-device Apple Intelligence via `FoundationModels`, strictly bounded/pre-digested input (`ReportSummaryInput`), guided generation (`@Generable`), explicit system prompt instructing the model to never invent findings and to describe "observation" findings as possibilities, not verdicts. Deterministic non-AI fallback template exists and is tested.
- `ManualCheck.swift` — an honest static checklist for things that can't be automated (clean-device first launch, consent before upload, Paid Apps Agreement, StoreKit sandbox robustness), gated correctly on whether StoreKit was actually analyzed.
- Markdown export (`ReportExporter`) — findings as a checkboxed checklist grouped by severity, tagged with guideline refs and a "heuristic — verify" marker, plus skipped-category and manual-check sections.
- PreFlight ships its own `PrivacyInfo.xcprivacy`, and it's accurate to what the app actually does (dogfooding checks out).
- Legal docs (`Legal/Privacy Policy.txt`, `Legal/Terms of Use.txt`) already exist in-repo.

**Real gaps found (not assumptions — confirmed by reading the code):**
- **No analysis history.** `ReportStore` persists exactly one JSON report per project (keyed by a hash of the project path); a new run overwrites the old one entirely. There is no run-to-run comparison anywhere in the UI, despite `AppState`'s own comment implying otherwise.
- **Test target isn't wired up.** `PreFlightTests/` has three real, well-written test files (`ASCJWTSignerTests`, `ModelTests`, `ScoringTests`), but `project.pbxproj` has no `PreFlightTests` target at all — these tests cannot currently run via `xcodebuild test` or in Xcode.
- **Zero analyzer-behavior tests.** Existing tests cover scoring math and model invariants well, but nothing verifies that, e.g., `ProjectAnalyzer` actually catches a placeholder bundle ID, or `PrivacyAnalyzer` actually flags a missing usage string, against a real fixture. This is a silent regression risk for a product whose entire pitch is "trust our findings."
- **No ASC "nutrition label" (App Privacy details) check.** `MetadataAnalyzer` never calls the app-privacy-declarations endpoint, so PreFlight cannot currently do the one thing Cleared differentiates hardest on: catching an SDK that collects data the developer never declared to Apple.
- **Accessibility and DeviceSupport analyzers are thin.** Two checks each, whole-project grep, no per-control analysis. This is the weakest part of the "Experience" pillar and the first thing a skeptical developer (or a competitor) would poke at.
- **No free entry point.** No paywall/IAP code was found; the app appears to be sold at a flat price with no trial or limited-scope free mode.
- No TODO/FIXME/stub markers anywhere in the source — the code that exists is clean and intentional, which is a good sign for what's there, but doesn't offset what's missing above.

---

## 5. Where PreFlight stands vs. competitors

1. **Behind:** analysis history/trend tracking (Appoval retains 30 days; we retain zero runs); CI/CD integration (Cleared, Appoval, Greenlight all have some story; we have none); runtime/behavioral verification (Greenlight already does this, free); free tier/trial (nearly every functioning competitor has one; we don't).
2. **Roughly equivalent:** "AI explains, doesn't invent findings" philosophy (Cleared independently converged on the same design); native-and-polished form factor (Cleared, Oxbit Preflight, App Store Scanner are all also native macOS — no longer a differentiator by itself).
3. **Better:** breadth/depth of ASC integration (deepest found in the survey); the Finding trust model's fact/observation clamping discipline (more rigorous than anything else found); StoreKit/subscription-specific analysis depth; the honest `ManualCheck` acknowledgment of what can't be automated.
4. **Fundamentally different:** nothing. The whole category — including us — has converged on the same basic shape (scan → map to guidelines → score → suggest fixes). This should be stated plainly rather than dressed up.
5. **Not yet built, potentially defensible if built well:** a narrow, reliable runtime-verification slice, *if* it's integrated tightly with the same evidence/guideline-reference architecture rather than bolted on — but this is contested ground (Greenlight, an OSS Simulator-driving Claude Code skill), not blue ocean, and should not be attempted before the static core is hardened and proven to sell.

---

## 6. Product strategy going forward

- **Positioning:** "The most trustworthy pre-submission check for solo and small-team Apple developers — built on facts you can verify, not AI guesses." Lead with the evidence/guideline-reference architecture, not with AI, not with "first mover."
- **Target customer (narrowed):** a solo or small-team Apple-native developer who ships occasionally (not continuously) and wants one high-confidence check before submitting — not a CI-embedded, high-frequency-shipping, or cross-platform team. That buyer is already being served (better, for free or via subscription) by Appoval, Cleared's CI story, and Greenlight.
- **Explicitly out of scope for the foreseeable future:** cross-platform (React Native/Flutter) input, agentic auto-fix/code-writing, a hosted CI/CD product with PR comments, multi-seat/team pricing, full Run Review.
- **Run Review (re-evaluated):** demote from "our differentiator" to "a post-1.0 bet to revisit once the static product has proven people will pay." It remains technically interesting (VISION.md's distribution-fork analysis is still correct and unchanged), but it is no longer blue ocean — Greenlight already does cloud runtime verification of the exact flows we'd have used as headline examples (Restore Purchases, account deletion, Sign in with Apple), and an open-source Claude Code skill already drives the Simulator. If we ever build it, the win condition is depth/reliability/integration with our evidence architecture, not the mere existence of the feature. Smallest useful version, if pursued: one narrow, semi-automated check (e.g., "does Restore Purchases actually restore a sandbox transaction") — not a full simulated session.
- **Trust framework:** keep leaning on what's already shipped (fact/observation clamping, evidence, guideline refs) and add the cheap, high-leverage trust primitives that are missing — an in-app methodology explainer, a dated/versioned ruleset stamp, and (post-launch) a published false-positive rate from real usage.
- **Business model:** keep one-time pricing at $12.99 — it's reasonable and matches the credible native competitors (Cleared, Oxbit Preflight, App Store Scanner) rather than the subscription players (Appoval, preflight.build). But **add a real free entry point** — recommended split: Project + Privacy + Review pillars run and display in full for free; Metadata (ASC) + StoreKit + AI summary + Markdown export require purchase. This mirrors Cleared's OSS-core/paid-shell model and Appoval's free-static-scan model, and draws the paywall exactly where the hardest engineering (ASC integration, AI) already lives.
- **Branding:** at least two live-or-launching products already use "PreFlight"/"Preflight" in this exact category (getpreflight.app, preflight.build), plus a direct App Store neighbor (Oxbit Preflight) and several OSS tools with "preflight" in the name. None of these collisions are commercially entrenched yet — this is a rare, cheap window to rename, but a full rename (bundle ID, ASC record, all copy, icon) is real production risk inside a 4-week launch window. **Recommendation: keep "PreFlight" for the v1.0 launch; do not rename now.** Mitigate cheaply with a distinguishing App Store subtitle/keyword strategy at launch, and treat the rename question as a resolved-before-*broad-marketing-spend* decision, not a resolved-before-*code-complete* one — revisit explicitly in Phase 6.

---

## 7. Execution plan

Status tags: `[x]` = verified complete in the codebase. `[ ]` = not done. Priority tags: `[P0]` critical, `[P1]` important, `[P2]` nice to have, `[P3]` future/post-v1.0.

### Phase 0 — Strategic decisions (this week)

- [x] Competitive research + strategic reassessment (this document).
- [ ] [P0] **Decide and commit:** free-tier boundary — recommended split is Project + Privacy + Review free; Metadata + StoreKit + AI + export paid.
- [ ] [P0] **Decide and commit:** keep the "PreFlight" name for v1.0 (recommended); schedule a rename/branding review for Phase 6, not before.
- [ ] [P0] **Decide and commit:** Mac App Store distribution vs. Developer ID for v1.0. Since Run Review is deferred, the sandbox constraint that would force this decision doesn't bind yet — recommend Mac App Store for v1.0, revisit only if/when Run Review work actually starts (per VISION.md's fork analysis).
- [ ] [P1] Quick informal trademark-adjacent check (USPTO/state search on "PreFlight" in software/dev-tools class) before any paid marketing spend — not urgent given no entrenched competitors found, but cheap to do now.

### Phase 1 — MVP completion (target: ~2 weeks)

- [ ] [P0] Add the `PreFlightTests` unit test target in Xcode (File → New → Target → Unit Testing Bundle, host in PreFlight) and confirm the three existing test files actually compile and run under `xcodebuild test`. This is a basic credibility issue for a product whose pitch is "trust our findings," and it's currently broken.
- [ ] [P0] Add analyzer fixture tests — one fixture (sample `AnalysisContext` or sample project) per analyzer proving each documented check actually fires: e.g. `ProjectAnalyzer` catches a `com.example.` bundle ID; `PrivacyAnalyzer` flags a missing `NSCameraUsageDescription` when `AVCaptureDevice` usage is present; `ReviewAnalyzer` flags `checkout.stripe.com`. Zero tests like this exist today.
- [ ] [P0] Add an ASC App Privacy ("nutrition label") check to `MetadataAnalyzer` — fetch the app's declared data-collection categories from App Store Connect and cross-reference against source-detected SDK/API usage patterns already scanned elsewhere in the codebase. This directly closes our clearest gap against Cleared's sharpest differentiator, and reuses ASC plumbing we already have.
- [ ] [P0] Implement the free-tier split decided in Phase 0: Project + Privacy + Review pillars fully functional with no purchase; Metadata + StoreKit + AI summary + export gated behind the $12.99 unlock.
- [ ] [P0] Give `ReportStore` real history: retain the last N (e.g. 10) timestamped reports per project instead of overwriting a single file; surface at minimum a score delta vs. the previous run in `ProjectView`/`HomeView`.
- [ ] [P0] Deepen `AccessibilityAnalyzer` and `DeviceSupportAnalyzer`, or narrow their public description to match actual depth before marketing an "Experience" pillar. Recommended minimum additions: a VoiceOver-trait presence check on custom controls, a minimum-tappable-target-size check, and (for DeviceSupport) explicit scoping language since it currently only checks iPad, not macOS resizing or visionOS despite the generic name.
- [ ] [P1] Add an in-app "How PreFlight knows this" methodology view (Settings/About) explaining the fact-vs-observation distinction at a product level — cheap trust-building on top of an architecture that already supports it.
- [ ] [P1] Add a dated/versioned ruleset stamp shown in Results (e.g. "Checked against the App Store Review Guidelines as of `<date>`") to counter the "stale AI knowledge" critique competitors actively market against.
- [ ] [P1] Add IAP (non-subscription) product checks via the ASC in-app-purchases endpoint in `MetadataAnalyzer` — currently only subscriptions are checked; one-time IAP products aren't cross-checked at all.
- [ ] [P1] Add a build-upload check (does a processed build actually exist for the current version?) to `MetadataAnalyzer` — currently never verified.
- [ ] [P2] Add a plain-text or PDF export option alongside the existing Markdown checklist, for attaching to App Review "notes to reviewer" or sharing with a non-technical stakeholder.
- [ ] [P2] Minimal CI wrapper (source-only checks, no ASC) around the existing engine — only if genuinely low-effort; most direct competitors already have some CI story, but this is not a launch blocker.

### Phase 2 — Validation (target: ~3–4 days, overlapping Phase 1)

- [ ] [P0] Dogfood against 3–5 real Xcode projects, ideally including at least one with a known past rejection, and confirm findings line up with the real, known cause.
- [ ] [P0] Recruit 3–5 external indie developers for a private beta; explicitly capture disagreements with findings as false-positive reports. Treat every confirmed false positive as a P0 bug — per VISION.md's own warning, "a virtual reviewer that cries wolf loses all credibility."
- [ ] [P1] Run the same test project through Cleared's and Appoval's free tiers and compare findings — confirm we're not missing something a free competitor catches trivially (especially the privacy-mismatch case).

### Phase 3 — Polish (target: ~1 week)

- [ ] [P1] Confirm the new `AppIcon.icon` asset (Icon Composer bundle, currently untracked) is actually wired into build settings as the shipping app icon.
- [ ] [P1] Onboarding copy pass reflecting the narrowed positioning decided in §6 (solo/indie Apple-native developer, trust-first messaging, not "AI-powered" as the headline).
- [ ] [P1] Audit empty/error states: no ASC key configured, ASC 401/404/429 responses, a project with zero findings, a pbxproj parse failure — confirm each degrades gracefully per `Analyzer.swift`'s "never throw" contract.
- [ ] [P2] Visual pass on `ResultsView`'s finding cards — since evidence/guideline-reference/confidence badges are the actual trust surface, they should be scannable at a glance, not buried in a `DisclosureGroup`.

### Phase 4 — Distribution readiness (target: ~3–5 days)

- [ ] [P0] Finalize the App Store Connect record and pricing ($12.99 one-time); confirm the free-tier mechanism decided in Phase 0 is implemented in an App-Review-compliant way (in-app unlock vs. a separate free app).
- [ ] [P0] Confirm `Legal/Privacy Policy.txt` and `Legal/Terms of Use.txt` (already in-repo) are hosted at stable public URLs and correctly linked from `SettingsView`'s About tab.
- [ ] [P1] Write App Store listing metadata and screenshots — and run PreFlight's own `MetadataAnalyzer` against PreFlight's own ASC record before submitting.
- [ ] [P1] Lock a distinguishing App Store subtitle/keyword strategy given the name-collision risk documented in §2.3 — a cheap mitigation short of a full rename.

### Phase 5 — Launch (target: 1–2 days + ongoing)

- [ ] [P1] Prepare a launch post (Show HN / Product Hunt) that's candid about the category being new and crowded rather than claiming to be first — this matches the evidence and is itself a trust signal.
- [ ] [P2] Direct outreach to a couple of indie-dev communities (r/iOSProgramming, Swift forums); lead with the deterministic/evidence architecture, not "AI tool" framing, given observed community skepticism toward generic AI claims in this research.

### Phase 6 — Post-launch (ongoing)

- [ ] [P1] Add an opt-in, privacy-respecting signal for users to mark a finding as "not actually a problem," to build a real, published false-positive rate over time.
- [ ] [P1] Revisit CI/CD integration once there's real evidence of repeat/recurring usage.
- [ ] [P2] Revisit the rename/branding decision from Phase 0 once there's real usage data on whether the name collisions are costing us App Store search ranking or causing support confusion.

### Phase 7 — Long-term differentiation (post-v1.0, months out)

- [ ] [P3] Smallest useful "Run Review" experiment: one narrow, semi-automated check (e.g., verify Restore Purchases actually restores a StoreKit sandbox transaction), gated behind Developer-ID distribution. Do not attempt a full simulator-driven session until this narrow slice is proven valuable and reliable.
- [ ] [P3] Revisit the distribution-fork decision (Mac App Store sandboxed + helper CLI vs. Developer ID) per VISION.md, required before any further Run Review work.
- [ ] [P3] Consider bring-your-own-key AI providers (Claude/OpenAI/Gemini) for users without an Apple-Intelligence-eligible Mac, mirroring Cleared's approach.
- [ ] [P3] Consider narrow cross-platform (React Native/Flutter) input support — only if there's a clear demand signal from the native beachhead first.
- [ ] [P3] Consider a full CI/CD product (hosted dashboard, PR comments) — Appoval/Cleared/Greenlight territory; revisit only once the native app has proven the trust model and there's demand pull.

---

## Out of scope (explicitly, do not build before v1.0)

- Agentic auto-fix / code-writing (Oxbit Preflight already does this; not core to our trust thesis, and higher-risk).
- Full Run Review / simulator-driven review sessions.
- Cross-platform (React Native/Flutter) project analysis.
- A hosted CI/CD product with PR comments.
- Multi-AI-provider / bring-your-own-key support.
- Team/agency multi-seat pricing and features.
- A full brand rename (revisit post-launch per Phase 6, not now).

---

## Reference

- **VISION.md** — the qualitative design philosophy (three pillars, finding quality bar, facts-vs-observations discipline, Run Review architecture options). Still accurate; not superseded by this document.
