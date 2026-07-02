import Foundation

final class ConfigStore {
    private let directoryURL: URL
    private let legacyConfigURL: URL
    let configURL: URL
    let lockURL: URL
    let logURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directoryURL = appSupport.appendingPathComponent("Clocktower", isDirectory: true)
        self.legacyConfigURL = directoryURL.appendingPathComponent("config.json")
        self.lockURL = directoryURL.appendingPathComponent("clocktower.lock")
        self.logURL = directoryURL.appendingPathComponent("clocktower.log")

        // The config lives in the app group container so the Control Center
        // extension (sandboxed) and the app can both read and write it.
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ClocktowerIntegration.appGroupID
        ) {
            self.configURL = group.appendingPathComponent("config.json")
        } else {
            self.configURL = legacyConfigURL
        }
    }

    func load() -> BellConfig {
        migrateLegacyConfigIfNeeded()
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(BellConfig.self, from: data) else {
            save(BellConfig.default)
            return .default
        }
        return config
    }

    func save(_ config: BellConfig) {
        guard let data = try? JSONEncoder.pretty.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: configURL, options: .atomic)
    }

    private func migrateLegacyConfigIfNeeded() {
        guard configURL != legacyConfigURL,
              !FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: legacyConfigURL.path) else { return }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.copyItem(at: legacyConfigURL, to: configURL)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
