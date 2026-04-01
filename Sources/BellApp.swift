import AppKit
import UserNotifications

@MainActor
final class BellApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private var config: BellConfig!
    private var preferencesWindowController: PreferencesWindowController?
    private let isTestMode = CommandLine.arguments.contains("--test")
    private let scheduledPrefix = "clocktower-scheduled-"

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.load()
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureNotifications()
        if isTestMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.fireBell(isTest: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                NSApp.terminate(nil)
            }
        } else {
            scheduleNotifications()
            Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.scheduleNotifications() }
            }
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

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @objc private func sendTestBell() {
        fireBell(isTest: true)
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

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let dates = nextTriggerDates(intervalMinutes: max(1, config.intervalMinutes), limit: 64)
        for date in dates {
            let content = UNMutableNotificationContent()
            content.title = config.title
            content.body = renderBody(for: date, isTest: false)
            if let soundName = config.soundName, !soundName.isEmpty {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).aiff"))
            } else {
                content.sound = .default
            }

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "\(scheduledPrefix)\(Int(date.timeIntervalSince1970))"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    private func nextTriggerDates(intervalMinutes: Int, limit: Int) -> [Date] {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = components.minute ?? 0
        let nextMinute = ((minute / intervalMinutes) + 1) * intervalMinutes

        var nextComponents = components
        nextComponents.second = 0

        if nextMinute >= 60 {
            nextComponents.minute = nextMinute - 60
            nextComponents.hour = (components.hour ?? 0) + 1
        } else {
            nextComponents.minute = nextMinute
        }

        guard let nextDate = calendar.date(from: nextComponents) else {
            return []
        }

        return (0..<limit).compactMap { offset in
            calendar.date(byAdding: .minute, value: offset * intervalMinutes, to: nextDate)
        }
    }

    private func fireBell(isTest: Bool) {
        if config.suppressWhenPresenting && isLikelyPresenting() {
            if isTestMode {
                NSApp.terminate(nil)
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = config.title
        content.body = renderBody(isTest: isTest)
        if let soundName = config.soundName, !soundName.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).aiff"))
        } else {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "clocktower-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func renderBody(for date: Date = Date(), isTest: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        let timeText = formatter.string(from: date)
        let body = config.bodyTemplate.replacingOccurrences(of: "{{time}}", with: timeText)
        return isTest ? "\(body) [test]" : body
    }

    private func isLikelyPresenting() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() else {
            return false
        }
        let targets = config.presentationApps.map { $0.lowercased() }
        return targets.contains { frontmost.contains($0) }
    }

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
        Task { @MainActor in
            NSApp.hide(nil)
        }
    }
}
