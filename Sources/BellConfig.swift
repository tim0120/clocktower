import Foundation

struct BellConfig: Codable {
    var isEnabled: Bool
    var intervalMinutes: Int
    var title: String
    var bodyTemplate: String
    var soundName: String?
    var suppressWhenPresenting: Bool
    var quietHoursEnabled: Bool
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int

    static let `default` = BellConfig(
        isEnabled: true,
        intervalMinutes: 30,
        title: "Clocktower",
        bodyTemplate: "It's {{time}}.",
        soundName: "Tink",
        suppressWhenPresenting: false,
        quietHoursEnabled: false,
        quietHoursStartMinutes: 18 * 60,
        quietHoursEndMinutes: 9 * 60
    )

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case intervalMinutes
        case title
        case bodyTemplate
        case soundName
        case suppressWhenPresenting
        case quietHoursEnabled
        case quietHoursStartMinutes
        case quietHoursEndMinutes
    }

    init(
        isEnabled: Bool,
        intervalMinutes: Int,
        title: String,
        bodyTemplate: String,
        soundName: String?,
        suppressWhenPresenting: Bool,
        quietHoursEnabled: Bool,
        quietHoursStartMinutes: Int,
        quietHoursEndMinutes: Int
    ) {
        self.isEnabled = isEnabled
        self.intervalMinutes = intervalMinutes
        self.title = title
        self.bodyTemplate = bodyTemplate
        self.soundName = soundName
        self.suppressWhenPresenting = suppressWhenPresenting
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? Self.default.intervalMinutes
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.default.title
        bodyTemplate = try container.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? Self.default.bodyTemplate
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName)
        suppressWhenPresenting = try container.decodeIfPresent(Bool.self, forKey: .suppressWhenPresenting) ?? Self.default.suppressWhenPresenting
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? Self.default.quietHoursEnabled
        quietHoursStartMinutes = try container.decodeIfPresent(Int.self, forKey: .quietHoursStartMinutes) ?? Self.default.quietHoursStartMinutes
        quietHoursEndMinutes = try container.decodeIfPresent(Int.self, forKey: .quietHoursEndMinutes) ?? Self.default.quietHoursEndMinutes
    }
}
