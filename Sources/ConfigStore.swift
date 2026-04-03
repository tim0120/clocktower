import Foundation

final class ConfigStore {
    private let directoryURL: URL
    let configURL: URL
    let lockURL: URL
    let logURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directoryURL = appSupport.appendingPathComponent("Clocktower", isDirectory: true)
        self.configURL = directoryURL.appendingPathComponent("config.json")
        self.lockURL = directoryURL.appendingPathComponent("clocktower.lock")
        self.logURL = directoryURL.appendingPathComponent("clocktower.log")
    }

    func load() -> BellConfig {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(BellConfig.self, from: data) else {
            save(BellConfig.default)
            return .default
        }
        return config
    }

    func save(_ config: BellConfig) {
        guard let data = try? JSONEncoder.pretty.encode(config) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: configURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
