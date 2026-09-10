import Foundation
import Testing
@testable import PreFlight

/// The links in AppLinks are force-unwrapped literals, and App Review rejects
/// builds whose paywall privacy/terms links don't resolve. These tests are what
/// make those force unwraps safe.
@Suite("App links")
struct AppLinksTests {
    @Test("Every link parses into a URL")
    func allLinksParse() {
        #expect(AppLinks.all.count == 4)
        for url in AppLinks.all {
            #expect(!url.absoluteString.isEmpty)
        }
    }

    @Test("Web links point at the canonical www.pre-flight.info host over HTTPS")
    func webLinksUseCanonicalHost() {
        let webLinks = [AppLinks.website, AppLinks.privacyPolicy, AppLinks.termsOfUse]
        for url in webLinks {
            #expect(url.scheme == "https")
            #expect(url.host() == "www.pre-flight.info")
        }
    }

    @Test("Privacy and terms resolve to their own pages")
    func legalLinksHaveDistinctPaths() {
        #expect(AppLinks.privacyPolicy.path() == "/privacy")
        #expect(AppLinks.termsOfUse.path() == "/terms")
        #expect(AppLinks.privacyPolicy != AppLinks.termsOfUse)
    }

    @Test("Support link is a mailto address")
    func supportLinkIsMailto() {
        #expect(AppLinks.support.scheme == "mailto")
    }
}
