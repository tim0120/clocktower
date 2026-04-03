import Foundation

actor AppLogger {
    static let shared = AppLogger()

    private let logURL: URL

    private init() {
        logURL = ConfigStore().logURL
    }

    func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"

        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}

func logAsync(_ message: String) {
    Task {
        await AppLogger.shared.log(message)
    }
}
