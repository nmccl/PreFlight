import Foundation
import Testing
@testable import PreFlight

/// PreFlight shipped with com.apple.security.network.server and didn't flag it,
/// because the unused-entitlement check only read a `.entitlements` file and
/// this project — like most modern Xcode projects — has none. Entitlements come
/// from ENABLE_* build settings instead. These tests pin that mapping.
@Suite("Entitlements generated from build settings")
struct GeneratedEntitlementsTests {
    private func target(_ settings: [String: String]) -> TargetInfo {
        TargetInfo(
            name: "App",
            productType: "com.apple.product-type.application",
            buildSettings: ["Release": settings]
        )
    }

    @Test("Incoming connections produce the network.server entitlement")
    func incomingConnectionsMapToServer() {
        let keys = GeneratedEntitlements.keys(for: target([
            "ENABLE_INCOMING_NETWORK_CONNECTIONS": "YES",
        ]))
        #expect(keys["com.apple.security.network.server"] == "true")
    }

    @Test("This is the exact configuration that got the app rejected")
    func theRejectedConfiguration() {
        // PreFlight's own Release settings at the time of the rejection.
        let keys = GeneratedEntitlements.keys(for: target([
            "ENABLE_APP_SANDBOX": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "ENABLE_INCOMING_NETWORK_CONNECTIONS": "YES",
            "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES",
            "ENABLE_USER_SELECTED_FILES": "readonly",
        ]))
        #expect(keys["com.apple.security.network.server"] == "true")
        #expect(keys["com.apple.security.network.client"] == "true")
        #expect(keys["com.apple.security.app-sandbox"] == "true")
        #expect(keys["com.apple.security.files.user-selected.read-only"] == "true")
    }

    @Test("The fixed configuration grants client but not server")
    func theFixedConfiguration() {
        let keys = GeneratedEntitlements.keys(for: target([
            "ENABLE_APP_SANDBOX": "YES",
            "ENABLE_INCOMING_NETWORK_CONNECTIONS": "NO",
            "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES",
            "ENABLE_USER_SELECTED_FILES": "readonly",
        ]))
        #expect(keys["com.apple.security.network.server"] == nil)
        #expect(keys["com.apple.security.network.client"] == "true")
    }

    @Test("Settings left at NO or empty grant nothing")
    func disabledSettingsGrantNothing() {
        let keys = GeneratedEntitlements.keys(for: target([
            "ENABLE_RESOURCE_ACCESS_CAMERA": "NO",
            "ENABLE_RESOURCE_ACCESS_LOCATION": "",
            "AUTOMATION_APPLE_EVENTS": "NO",
        ]))
        #expect(keys.isEmpty)
    }

    @Test("File access level selects read-only versus read-write")
    func accessLevelMapping() {
        let readOnly = GeneratedEntitlements.keys(for: target(["ENABLE_USER_SELECTED_FILES": "readonly"]))
        #expect(readOnly["com.apple.security.files.user-selected.read-only"] == "true")
        #expect(readOnly["com.apple.security.files.user-selected.read-write"] == nil)

        let readWrite = GeneratedEntitlements.keys(for: target(["ENABLE_USER_SELECTED_FILES": "readwrite"]))
        #expect(readWrite["com.apple.security.files.user-selected.read-write"] == "true")
        #expect(readWrite["com.apple.security.files.user-selected.read-only"] == nil)
    }

    @Test("Hardened runtime exceptions map to their cs.* entitlements")
    func hardenedRuntimeExceptions() {
        let keys = GeneratedEntitlements.keys(for: target([
            "RUNTIME_EXCEPTION_ALLOW_JIT": "YES",
            "RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION": "YES",
            "RUNTIME_EXCEPTION_DEBUGGING_TOOL": "YES",
        ]))
        #expect(keys["com.apple.security.cs.allow-jit"] == "true")
        #expect(keys["com.apple.security.cs.disable-library-validation"] == "true")
        #expect(keys["com.apple.security.cs.debugger"] == "true")
    }

    @Test("A project with no capabilities produces no entitlements")
    func emptyProject() {
        #expect(GeneratedEntitlements.keys(for: target([:])).isEmpty)
    }

    @Test("Release settings win over other configurations")
    func releaseWins() {
        // What ships is the Release value, so that's what must be analyzed.
        let mixed = TargetInfo(
            name: "App",
            productType: "com.apple.product-type.application",
            buildSettings: [
                "Debug": ["ENABLE_INCOMING_NETWORK_CONNECTIONS": "YES"],
                "Release": ["ENABLE_INCOMING_NETWORK_CONNECTIONS": "NO"],
            ]
        )
        #expect(GeneratedEntitlements.keys(for: mixed)["com.apple.security.network.server"] == nil)
    }
}
