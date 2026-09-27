import Foundation

/// Reconstructs the entitlements Xcode generates from build settings.
///
/// Modern Xcode projects usually have no `.entitlements` file at all. Instead,
/// capabilities are toggled with `ENABLE_*` and `RUNTIME_EXCEPTION_*` build
/// settings, and the entitlements plist is synthesized at build time. Any check
/// that only reads `CODE_SIGN_ENTITLEMENTS` therefore sees nothing and silently
/// passes — which is how an app can ship with a sandbox entitlement it doesn't
/// use and get an automated rejection for it.
///
/// Mapping these settings back to their entitlement keys makes the generated
/// set visible to the analyzers, so it can be checked the same way a
/// hand-written entitlements file is.
enum GeneratedEntitlements {

    /// Build settings whose value is YES/NO and that map to a single entitlement key.
    private static let booleanSettings: [String: String] = [
        "ENABLE_APP_SANDBOX": "com.apple.security.app-sandbox",
        "ENABLE_INCOMING_NETWORK_CONNECTIONS": "com.apple.security.network.server",
        "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "com.apple.security.network.client",
        "ENABLE_RESOURCE_ACCESS_CAMERA": "com.apple.security.device.camera",
        "ENABLE_RESOURCE_ACCESS_AUDIO_INPUT": "com.apple.security.device.audio-input",
        "ENABLE_RESOURCE_ACCESS_BLUETOOTH": "com.apple.security.device.bluetooth",
        "ENABLE_RESOURCE_ACCESS_USB": "com.apple.security.device.usb",
        "ENABLE_RESOURCE_ACCESS_PRINTING": "com.apple.security.print",
        "ENABLE_RESOURCE_ACCESS_LOCATION": "com.apple.security.personal-information.location",
        "ENABLE_RESOURCE_ACCESS_CONTACTS": "com.apple.security.personal-information.addressbook",
        "ENABLE_RESOURCE_ACCESS_CALENDARS": "com.apple.security.personal-information.calendars",
        "ENABLE_RESOURCE_ACCESS_PHOTO_LIBRARY": "com.apple.security.personal-information.photos-library",
        "AUTOMATION_APPLE_EVENTS": "com.apple.security.automation.apple-events",
        // Hardened runtime exceptions. Each one weakens a protection, and
        // reviewers ask for unjustified ones to be removed.
        "RUNTIME_EXCEPTION_ALLOW_JIT": "com.apple.security.cs.allow-jit",
        "RUNTIME_EXCEPTION_ALLOW_UNSIGNED_EXECUTABLE_MEMORY": "com.apple.security.cs.allow-unsigned-executable-memory",
        "RUNTIME_EXCEPTION_ALLOW_DYLD_ENVIRONMENT_VARIABLES": "com.apple.security.cs.allow-dyld-environment-variables",
        "RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION": "com.apple.security.cs.disable-library-validation",
        "RUNTIME_EXCEPTION_DISABLE_EXECUTABLE_PAGE_PROTECTION": "com.apple.security.cs.disable-executable-page-protection",
        "RUNTIME_EXCEPTION_DEBUGGING_TOOL": "com.apple.security.cs.debugger",
    ]

    /// Settings whose value selects between read-only and read-write access.
    /// Keyed by setting name, mapping the setting's value to an entitlement key.
    private static let accessLevelSettings: [String: (readOnly: String, readWrite: String)] = [
        "ENABLE_USER_SELECTED_FILES": (
            "com.apple.security.files.user-selected.read-only",
            "com.apple.security.files.user-selected.read-write"
        ),
        "ENABLE_FILE_ACCESS_DOWNLOADS_FOLDER": (
            "com.apple.security.files.downloads.read-only",
            "com.apple.security.files.downloads.read-write"
        ),
        "ENABLE_FILE_ACCESS_PICTURE_FOLDER": (
            "com.apple.security.assets.pictures.read-only",
            "com.apple.security.assets.pictures.read-write"
        ),
        "ENABLE_FILE_ACCESS_MUSIC_FOLDER": (
            "com.apple.security.assets.music.read-only",
            "com.apple.security.assets.music.read-write"
        ),
        "ENABLE_FILE_ACCESS_MOVIES_FOLDER": (
            "com.apple.security.assets.movies.read-only",
            "com.apple.security.assets.movies.read-write"
        ),
    ]

    /// The entitlement keys a target's build settings will produce, mapped to
    /// their string value. Only granted entitlements are included: a setting
    /// left at NO or empty grants nothing and is omitted.
    static func keys(for target: TargetInfo) -> [String: String] {
        var result: [String: String] = [:]

        for (setting, entitlement) in booleanSettings {
            guard let value = target.setting(setting)?.uppercased(), value == "YES" else { continue }
            result[entitlement] = "true"
        }

        for (setting, keys) in accessLevelSettings {
            guard let value = target.setting(setting)?.lowercased() else { continue }
            switch value {
            case "readonly": result[keys.readOnly] = "true"
            case "readwrite": result[keys.readWrite] = "true"
            default: break  // empty or an unrecognized value grants nothing
            }
        }

        return result
    }
}
