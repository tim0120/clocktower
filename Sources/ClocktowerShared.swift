import Foundation

enum ClocktowerIntegration {
    static let appGroupID = "group.com.tim0120.clocktower"
    static let controlKind = "com.tim0120.clocktower.control.enabled"
}

extension Notification.Name {
    static let clocktowerConfigDidChange = Notification.Name("com.tim0120.clocktower.configDidChange")
}
