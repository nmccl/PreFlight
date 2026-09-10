import Foundation
import Testing
@testable import PreFlight

@Suite("Code vs. prose")
struct CodeOnlyTests {
    @Test("A framework named in a line comment is not evidence of using it")
    func lineCommentStripped() {
        let source = """
            // Checks whether the app uses AVCaptureDevice for the camera.
            let value = 1
            """
        let code = SourceEvidence.codeOnly(source)
        #expect(!code.contains("AVCaptureDevice"))
        #expect(code.contains("let value = 1"))
    }

    @Test("A framework named in a block comment is not evidence of using it")
    func blockCommentStripped() {
        let source = """
            /* CLLocationManager requires a usage description.
               /* nested */ still a comment */
            import Foundation
            """
        let code = SourceEvidence.codeOnly(source)
        #expect(!code.contains("CLLocationManager"))
        #expect(code.contains("import Foundation"))
    }

    @Test("An analyzer's own detection pattern in a string literal is not usage")
    func stringLiteralStripped() {
        // This is exactly the self-matching case: an analyzer holding the
        // pattern it searches for.
        let source = #"""
            let patterns = ["UIWebView", "AVCaptureDevice", "createAccount"]
            """#
        let code = SourceEvidence.codeOnly(source)
        #expect(!code.contains("UIWebView"))
        #expect(!code.contains("AVCaptureDevice"))
        #expect(!code.contains("createAccount"))
        #expect(code.contains("let patterns"))
    }

    @Test("Guideline text in a multiline string literal is not usage")
    func multilineStringStripped() {
        let source = #"""
            let guidance = """
                Apps using UIImagePickerController need NSCameraUsageDescription.
                """
            """#
        let code = SourceEvidence.codeOnly(source)
        #expect(!code.contains("UIImagePickerController"))
        #expect(!code.contains("NSCameraUsageDescription"))
    }

    @Test("Real API calls survive stripping")
    func realUsageSurvives() {
        let source = """
            import AVFoundation
            let device = AVCaptureDevice.default(for: .video)
            """
        let code = SourceEvidence.codeOnly(source)
        #expect(code.contains("AVCaptureDevice"))
        #expect(code.contains("import AVFoundation"))
    }

    @Test("An escaped quote doesn't leak the rest of the file")
    func escapedQuoteHandled() {
        let source = #"""
            let a = "he said \"UIWebView\" once"
            let b = AVCaptureDevice.self
            """#
        let code = SourceEvidence.codeOnly(source)
        #expect(!code.contains("UIWebView"))
        #expect(code.contains("AVCaptureDevice"))
    }
}

@Suite("Vendored dependency detection")
struct VendoredSourceTests {
    @Test("A sibling package directory is vendored, the app's own is not")
    func packageRootDirectory() {
        let roots: Set<String> = ["posthog"]
        #expect(SourceEvidence.isVendored(
            "PostHog/PostHog/Autocapture/UIView+PostHogLabel.swift",
            packageRootDirectories: roots,
            resolvedPackageNames: []
        ))
        #expect(!SourceEvidence.isVendored(
            "PreFlight/Views/PaywallView.swift",
            packageRootDirectories: roots,
            resolvedPackageNames: []
        ))
    }

    @Test("Conventional dependency directories are vendored")
    func conventionalDirectories() {
        let paths = [
            "Pods/Alamofire/Source/Request.swift",
            "Carthage/Checkouts/Lib/Lib.swift",
            ".build/checkouts/swift-log/Logging.swift",
            "SourcePackages/checkouts/pkg/File.swift",
            "ThirdParty/Vendor/Thing.swift",
        ]
        for path in paths {
            #expect(
                SourceEvidence.isVendored(path, packageRootDirectories: [], resolvedPackageNames: []),
                "\(path) should be vendored"
            )
        }
    }

    @Test("A resolved package identity matches its checkout directory name")
    func resolvedNameMatchesLoosely() {
        // Package.resolved says "posthog-ios"; the directory is "PostHog".
        let resolved: Set<String> = [SourceEvidence.normalizePackageName("posthog-ios")]
        #expect(SourceEvidence.isVendored(
            "PostHog/PostHog/Logs/PostHogLogger.swift",
            packageRootDirectories: [],
            resolvedPackageNames: resolved
        ))
    }

    @Test("A local package the developer owns is not treated as vendored")
    func localPackagesNotVendored() {
        #expect(!SourceEvidence.isVendored(
            "Packages/MyFeature/Sources/MyFeature.swift",
            packageRootDirectories: [],
            resolvedPackageNames: []
        ))
    }

    @Test("Application code is neither test nor vendored")
    func applicationCodeClassification() {
        let app = EvidenceSourceFile(
            relativePath: "PreFlight/Views/HomeView.swift",
            content: "", isTestFile: false, isVendored: false
        )
        let test = EvidenceSourceFile(
            relativePath: "PreFlightTests/ModelTests.swift",
            content: "", isTestFile: true, isVendored: false
        )
        let vendored = EvidenceSourceFile(
            relativePath: "PostHog/PostHog/PostHogSDK.swift",
            content: "", isTestFile: false, isVendored: true
        )
        #expect(app.isApplicationCode)
        #expect(!test.isApplicationCode)
        #expect(!vendored.isApplicationCode)
    }
}

@Suite("Platform gating")
struct TargetPlatformsTests {
    private func target(_ settings: [String: String]) -> TargetInfo {
        TargetInfo(
            name: "App",
            productType: "com.apple.product-type.application",
            buildSettings: ["Release": settings]
        )
    }

    @Test("A macOS-only app doesn't target iOS")
    func macOnly() {
        let platforms = TargetPlatforms(appTargets: [target(["SUPPORTED_PLATFORMS": "macosx"])])
        #expect(platforms.supportsMac)
        #expect(!platforms.supportsIOS)
        #expect(platforms.displayName == "macOS")
    }

    @Test("A device family marks the target as iOS")
    func iosViaDeviceFamily() {
        let platforms = TargetPlatforms(appTargets: [target(["TARGETED_DEVICE_FAMILY": "1,2"])])
        #expect(platforms.supportsIOS)
    }

    @Test("Mac Catalyst counts as both, since UIKit applies")
    func macCatalyst() {
        let platforms = TargetPlatforms(appTargets: [target(["SUPPORTS_MACCATALYST": "YES"])])
        #expect(platforms.supportsIOS)
        #expect(platforms.supportsMac)
    }

    @Test("Unknown platform settings run every check rather than silently skipping")
    func unknownFallsBackToAll() {
        let platforms = TargetPlatforms(appTargets: [target([:])])
        #expect(platforms.supportsIOS)
        #expect(platforms.supportsMac)
    }
}
