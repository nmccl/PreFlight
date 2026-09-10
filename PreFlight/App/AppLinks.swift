import Foundation

/// Canonical public URLs for PreFlight.
///
/// App Review requires the privacy policy and terms of use to be reachable
/// from anywhere a purchase is offered, so every screen links to the same
/// place from here rather than hardcoding its own string.
///
/// The force unwraps are safe: these are compile-time literals, and
/// `AppLinksTests` asserts each one parses.
enum AppLinks {
    static let website = URL(string: "https://www.pre-flight.info")!
    static let privacyPolicy = URL(string: "https://www.pre-flight.info/privacy")!
    static let termsOfUse = URL(string: "https://www.pre-flight.info/terms")!
    static let support = URL(string: "mailto:contact@noahmcclung.com")!

    /// Every link above, for the test that verifies they all parse.
    static let all: [URL] = [website, privacyPolicy, termsOfUse, support]
}
