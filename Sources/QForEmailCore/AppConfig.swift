import Foundation

public enum FilingMode: String, Codable, CaseIterable, Equatable, Sendable {
    case review
    case auto
}

public enum MailScope: String, Codable, CaseIterable, Equatable, Sendable {
    case newOnly
    case includeExisting
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var endpointURL: String
    public var model: String
    public var filingMode: FilingMode
    public var scope: MailScope
    public var sortingEnabled: Bool
    public var enabledAt: Date?
    public var minimumConfidence: Double
    public var batchSize: Int
    public var autoSortMinutes: Int
    public var launchAtLogin: Bool
    public var enabledCategoryIDs: Set<String>
    public var disabledAccountNames: Set<String>
    public var remoteEndpointConfirmed: Bool
    public var verifiedFingerprint: String?
    public var paused: Bool

    public init(
        endpointURL: String = "",
        model: String = "",
        filingMode: FilingMode = .review,
        scope: MailScope = .newOnly,
        sortingEnabled: Bool = false,
        enabledAt: Date? = nil,
        minimumConfidence: Double = 0.75,
        batchSize: Int = 20,
        autoSortMinutes: Int = 0,
        launchAtLogin: Bool = false,
        enabledCategoryIDs: Set<String> = Category.defaultEnabledIDs,
        disabledAccountNames: Set<String> = [],
        remoteEndpointConfirmed: Bool = false,
        verifiedFingerprint: String? = nil,
        paused: Bool = false
    ) {
        self.endpointURL = endpointURL
        self.model = model
        self.filingMode = filingMode
        self.scope = scope
        self.sortingEnabled = sortingEnabled
        self.enabledAt = enabledAt
        self.minimumConfidence = minimumConfidence
        self.batchSize = batchSize
        self.autoSortMinutes = autoSortMinutes
        self.launchAtLogin = launchAtLogin
        self.enabledCategoryIDs = enabledCategoryIDs
        self.disabledAccountNames = disabledAccountNames
        self.remoteEndpointConfirmed = remoteEndpointConfirmed
        self.verifiedFingerprint = verifiedFingerprint
        self.paused = paused
    }

    public static let `default` = AppConfig()
}

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .default }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppConfig.self, from: data)
    }

    public func save(_ config: AppConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
