import Foundation

// Everything in the ASC layer is nonisolated: it's pure data and networking
// with no UI state, and analyzers must be able to use it off the main actor.

nonisolated enum ASCClientError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case rateLimited
    case http(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The App Store Connect request URL was invalid."
        case .unauthorized:
            "App Store Connect rejected the API key. Check the Issuer ID, Key ID, and .p8 file in Settings."
        case .notFound:
            "The requested resource doesn't exist on App Store Connect."
        case .rateLimited:
            "App Store Connect rate limit reached. Try again in a few minutes."
        case .http(let code):
            "App Store Connect returned an unexpected error (HTTP \(code))."
        case .network(let message):
            "Couldn't reach App Store Connect: \(message)"
        }
    }
}

/// The JSON:API envelope every ASC collection response uses.
nonisolated struct ASCCollection<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let data: [ASCResource<Attributes>]
}

/// The envelope for to-one relationships; data is null when the related
/// resource hasn't been created.
nonisolated struct ASCDocument<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let data: ASCResource<Attributes>?
}

nonisolated struct ASCResource<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let id: String
    let attributes: Attributes
}

/// A deliberately minimal App Store Connect REST client: just the GET
/// endpoints the analyzers need, not a full SDK.
nonisolated struct ASCClient: Sendable {
    let credentials: ASCCredentials
    private let signer = ASCJWTSigner()
    private static let baseURL = "https://api.appstoreconnect.apple.com"

    // MARK: Attribute payloads (only the fields we check)

    nonisolated struct AppAttributes: Decodable, Sendable {
        let name: String?
        let bundleId: String?
    }

    nonisolated struct AppInfoAttributes: Decodable, Sendable {}

    nonisolated struct AppInfoLocalizationAttributes: Decodable, Sendable {
        let locale: String?
        let privacyPolicyUrl: String?
    }

    nonisolated struct AppStoreVersionAttributes: Decodable, Sendable {
        let versionString: String?
        let appStoreState: String?
    }

    nonisolated struct AppStoreVersionLocalizationAttributes: Decodable, Sendable {
        let locale: String?
        let description: String?
        let keywords: String?
        let supportUrl: String?
        let marketingUrl: String?
    }

    nonisolated struct EULAAttributes: Decodable, Sendable {
        let agreementText: String?
    }

    nonisolated struct AppStoreReviewDetailAttributes: Decodable, Sendable {
        let demoAccountRequired: Bool?
        let demoAccountName: String?
        let notes: String?
    }

    nonisolated struct SubscriptionGroupAttributes: Decodable, Sendable {
        let referenceName: String?
    }

    nonisolated struct SubscriptionAttributes: Decodable, Sendable {
        let name: String?
        let productId: String?
        let state: String?
    }

    nonisolated struct AppScreenshotSetAttributes: Decodable, Sendable {
        let screenshotDisplayType: String?
    }

    /// App Privacy nutrition label declaration. The `category` field is the
    /// ASC data-category string (e.g. "DEVICE_ID", "PURCHASE_HISTORY").
    /// Uses `try?` at call sites so a schema change degrades gracefully.
    nonisolated struct AppPrivacyDeclarationAttributes: Decodable, Sendable {
        let category: String?
    }

    // MARK: Endpoints

    func app(forBundleID bundleID: String) async throws -> ASCResource<AppAttributes>? {
        let apps: ASCCollection<AppAttributes> = try await get(
            "/v1/apps",
            query: [URLQueryItem(name: "filter[bundleId]", value: bundleID)]
        )
        return apps.data.first
    }

    func appInfoLocalizations(forAppID appID: String) async throws -> [ASCResource<AppInfoLocalizationAttributes>] {
        let infos: ASCCollection<AppInfoAttributes> = try await get("/v1/apps/\(appID)/appInfos", query: [])
        var localizations: [ASCResource<AppInfoLocalizationAttributes>] = []
        for info in infos.data {
            let batch: ASCCollection<AppInfoLocalizationAttributes> = try await get(
                "/v1/appInfos/\(info.id)/appInfoLocalizations",
                query: []
            )
            localizations.append(contentsOf: batch.data)
        }
        return localizations
    }

    func latestAppStoreVersion(forAppID appID: String) async throws -> ASCResource<AppStoreVersionAttributes>? {
        let versions: ASCCollection<AppStoreVersionAttributes> = try await get(
            "/v1/apps/\(appID)/appStoreVersions",
            query: [URLQueryItem(name: "limit", value: "1")]
        )
        return versions.data.first
    }

    func appStoreVersionLocalizations(forVersionID versionID: String) async throws -> [ASCResource<AppStoreVersionLocalizationAttributes>] {
        let batch: ASCCollection<AppStoreVersionLocalizationAttributes> = try await get(
            "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations",
            query: []
        )
        return batch.data
    }

    /// The custom EULA, or nil when the app uses Apple's standard agreement.
    func endUserLicenseAgreement(forAppID appID: String) async throws -> ASCResource<EULAAttributes>? {
        try await getToOne("/v1/apps/\(appID)/endUserLicenseAgreement")
    }

    /// Reviewer-facing info (demo account, notes), or nil when never filled in.
    func appStoreReviewDetail(forVersionID versionID: String) async throws -> ASCResource<AppStoreReviewDetailAttributes>? {
        try await getToOne("/v1/appStoreVersions/\(versionID)/appStoreReviewDetail")
    }

    func subscriptionGroups(forAppID appID: String) async throws -> [ASCResource<SubscriptionGroupAttributes>] {
        let groups: ASCCollection<SubscriptionGroupAttributes> = try await get(
            "/v1/apps/\(appID)/subscriptionGroups",
            query: []
        )
        return groups.data
    }

    func subscriptions(forGroupID groupID: String) async throws -> [ASCResource<SubscriptionAttributes>] {
        let subscriptions: ASCCollection<SubscriptionAttributes> = try await get(
            "/v1/subscriptionGroups/\(groupID)/subscriptions",
            query: []
        )
        return subscriptions.data
    }

    func screenshotSets(forLocalizationID localizationID: String) async throws -> [ASCResource<AppScreenshotSetAttributes>] {
        let sets: ASCCollection<AppScreenshotSetAttributes> = try await get(
            "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets",
            query: []
        )
        return sets.data
    }

    /// App Privacy (nutrition label) declarations. Returns an empty array when
    /// no data types have been declared yet. Uses `try?` at call sites so
    /// a 404 or unexpected schema degrades gracefully rather than failing the run.
    func appPrivacyDeclarations(forAppID appID: String) async throws -> [ASCResource<AppPrivacyDeclarationAttributes>] {
        let result: ASCCollection<AppPrivacyDeclarationAttributes> = try await get(
            "/v1/apps/\(appID)/appPrivacyDeclarations",
            query: []
        )
        return result.data
    }

    // MARK: Transport

    /// Fetches a to-one relationship; a 404 or null data both mean "not set".
    private func getToOne<T: Decodable & Sendable>(_ path: String) async throws -> ASCResource<T>? {
        do {
            let document: ASCDocument<T> = try await get(path, query: [])
            return document.data
        } catch ASCClientError.notFound {
            return nil
        }
    }

    private func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard var components = URLComponents(string: Self.baseURL) else {
            throw ASCClientError.invalidURL
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw ASCClientError.invalidURL
        }

        var request = URLRequest(url: url)
        let token = try signer.token(for: credentials)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ASCClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ASCClientError.network("No HTTP response.")
        }
        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ASCClientError.network("Unexpected response format.")
            }
        case 401, 403:
            throw ASCClientError.unauthorized
        case 404:
            throw ASCClientError.notFound
        case 429:
            throw ASCClientError.rateLimited
        default:
            throw ASCClientError.http(http.statusCode)
        }
    }
}
