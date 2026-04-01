import Foundation

struct BellConfig: Codable {
    var intervalMinutes: Int
    var title: String
    var bodyTemplate: String
    var soundName: String?
    var suppressWhenPresenting: Bool

    static let `default` = BellConfig(
        intervalMinutes: 30,
        title: "Clocktower",
        bodyTemplate: "It's {{time}}.",
        soundName: "Tink",
        suppressWhenPresenting: false
    )
}
