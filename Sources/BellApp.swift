import AppKit
import UserNotifications

@MainActor
final class BellApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private var config: BellConfig!
    private var preferencesWindowController: PreferencesWindowController?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.load()
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        scheduleNotifications()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleNotifications() }
        }
    }

    private func configureStatusItem() {
        if let image = NSImage(systemSymbolName: "circlebadge", accessibilityDescription: "Clocktower") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "Bell"
        }
        statusItem.button?.toolTip = "Clocktower"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Send Test Bell", action: #selector(sendTestBell), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func sendTestBell() {
        sendNotification(body: "\(renderBody()) [test]")
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                configStore: configStore,
                config: config
            ) { [weak self] updatedConfig in
                self?.config = updatedConfig
                self?.scheduleNotifications()
                self?.preferencesWindowController = nil
            }
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.configURL)
    }

    @objc private func reloadConfig() {
        config = configStore.load()
        scheduleNotifications()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Scheduling

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for date in nextTriggerDates() {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "clocktower-\(Int(date.timeIntervalSince1970))",
                content: makeContent(body: renderBody(for: date)),
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func nextTriggerDates() -> [Date] {
        let interval = max(1, config.intervalMinutes)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        let minute = components.minute ?? 0

        var next = components
        next.second = 0
        let nextMinute = ((minute / interval) + 1) * interval
        if nextMinute >= 60 {
            next.minute = nextMinute - 60
            next.hour = (components.hour ?? 0) + 1
        } else {
            next.minute = nextMinute
        }

        guard let start = calendar.date(from: next) else { return [] }
        return (0..<64).compactMap { calendar.date(byAdding: .minute, value: $0 * interval, to: start) }
    }

    // MARK: - Notifications

    private func makeContent(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = config.title
        content.body = body
        if let name = config.soundName, !name.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(name).aiff"))
        } else {
            content.sound = .default
        }
        return content
    }

    private func sendNotification(body: String) {
        if config.suppressWhenPresenting, isLikelyPresenting() { return }

        let request = UNNotificationRequest(
            identifier: "clocktower-\(UUID().uuidString)",
            content: makeContent(body: body),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func renderBody(for date: Date = Date()) -> String {
        config.bodyTemplate.replacingOccurrences(of: "{{time}}", with: Self.timeFormatter.string(from: date))
    }

    private func isLikelyPresenting() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() else {
            return false
        }
        return config.presentationApps.contains { frontmost.contains($0.lowercased()) }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
