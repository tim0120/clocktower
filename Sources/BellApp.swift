import AppKit
import CoreGraphics
import UserNotifications

@MainActor
final class BellApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private var config: BellConfig!
    private var preferencesWindowController: PreferencesWindowController?
    private var enabledMenuItem: NSMenuItem?
    private var isScreenLocked = false
    private var isScreenAsleep = false
    private var awaySessionStart: Date?
    private nonisolated(unsafe) var lastNonSelfApp: NSRunningApplication?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    private var isCurrentlyAway: Bool {
        isScreenLocked || isScreenAsleep
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If we became active unexpectedly (e.g. user clicked a notification),
        // immediately return focus to the previous app.
        if preferencesWindowController == nil {
            lastNonSelfApp?.activate(options: .activateIgnoringOtherApps)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.load()
        logAsync("app did-finish-launching enabled=\(config.isEnabled) intervalMinutes=\(config.intervalMinutes) quietHoursEnabled=\(config.quietHoursEnabled) awayCatchUpEnabled=\(config.awayCatchUpEnabled)")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                logAsync("notifications authorization-error \(error.localizedDescription)")
            } else {
                logAsync("notifications authorization granted=\(granted)")
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastNonSelfApp = app
        }
        lastNonSelfApp = NSWorkspace.shared.frontmostApplication
        configureAwayObservers()

        scheduleNotifications()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleNotifications() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logAsync("app will-terminate")
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
        let enabledMenuItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        self.enabledMenuItem = enabledMenuItem
        menu.addItem(enabledMenuItem)
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Send Test Bell", action: #selector(sendTestBell), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Clear Notifications", action: #selector(clearNotificationsFromMenu), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        refreshStatusUI()
    }

    // MARK: - Menu actions

    @objc private func sendTestBell() {
        guard shouldNotify(at: Date(), context: "test") else {
            logAsync("notification test skipped")
            return
        }
        logAsync("notification test requested")
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
                self?.refreshStatusUI()
                self?.preferencesWindowController = nil
            }
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openConfig() {
        logAsync("menu open-config")
        NSWorkspace.shared.open(configStore.configURL)
    }

    @objc private func openLogs() {
        logAsync("menu open-logs")
        NSWorkspace.shared.open(configStore.logURL)
    }

    @objc private func reloadConfig() {
        config = configStore.load()
        logAsync("menu reload-config enabled=\(config.isEnabled) intervalMinutes=\(config.intervalMinutes) quietHoursEnabled=\(config.quietHoursEnabled)")
        scheduleNotifications()
        refreshStatusUI()
    }

    @objc private func clearNotificationsFromMenu() {
        clearNotifications(reason: "menu")
    }

    @objc private func toggleEnabled() {
        config.isEnabled.toggle()
        configStore.save(config)
        logAsync("menu toggle-enabled isEnabled=\(config.isEnabled)")
        scheduleNotifications()
        refreshStatusUI()
    }

    @objc private func quit() {
        logAsync("menu quit")
        NSApp.terminate(nil)
    }

    // MARK: - Scheduling

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        clearNotifications(reason: "schedule")
        guard config.isEnabled else {
            logAsync("schedule skipped because Clocktower is disabled")
            return
        }
        guard !isCurrentlyAway else {
            logAsync("schedule skipped because user is away")
            return
        }

        var scheduledCount = 0
        for date in nextTriggerDates() {
            guard shouldNotify(at: date, context: "scheduled") else { continue }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "clocktower-\(Int(date.timeIntervalSince1970))",
                content: makeContent(body: renderBody(for: date)),
                trigger: trigger
            )
            center.add(request) { error in
                if let error {
                    logAsync("schedule add-error at=\(date.ISO8601Format()) error=\(error.localizedDescription)")
                }
            }
            scheduledCount += 1
        }
        logAsync("schedule completed count=\(scheduledCount)")
    }

    private func nextTriggerDates() -> [Date] {
        guard let start = firstTriggerDate(after: Date()) else { return [] }
        let interval = max(1, config.intervalMinutes)
        let calendar = Calendar.current
        return (0..<64).compactMap { calendar.date(byAdding: .minute, value: $0 * interval, to: start) }
    }

    private func firstTriggerDate(after date: Date) -> Date? {
        let interval = max(1, config.intervalMinutes)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
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

        return calendar.date(from: next)
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

    private func sendNotification(body: String, context: String = "immediate") {
        guard config.isEnabled, shouldNotify(at: Date(), context: context) else {
            logAsync("notification \(context) skipped")
            return
        }

        let request = UNNotificationRequest(
            identifier: "clocktower-\(UUID().uuidString)",
            content: makeContent(body: body),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logAsync("notification \(context) add-error \(error.localizedDescription)")
            } else {
                logAsync("notification \(context) queued")
            }
        }
    }

    private func renderBody(for date: Date = Date()) -> String {
        config.bodyTemplate.replacingOccurrences(of: "{{time}}", with: Self.timeFormatter.string(from: date))
    }

    private func clearNotifications(reason: String) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        logAsync("notifications cleared reason=\(reason)")
    }

    private func shouldNotify(at date: Date, context: String) -> Bool {
        if let reason = notificationBlockReason(at: date, respectAwayState: true) {
            logAsync("notify blocked context=\(context) reason=\(reason) at=\(date.ISO8601Format())")
            return false
        }
        return true
    }

    private func notificationBlockReason(at date: Date, respectAwayState: Bool) -> String? {
        if !config.isEnabled {
            return "disabled"
        }

        if respectAwayState, isCurrentlyAway {
            return "away"
        }

        if config.quietHoursEnabled, isWithinQuietHours(date) {
            return "quiet-hours"
        }

        if config.suppressWhenPresenting, date.timeIntervalSinceNow < 60, isLikelyPresenting() {
            return "presenting"
        }

        return nil
    }

    private func isWithinQuietHours(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = normalizedMinutes(config.quietHoursStartMinutes)
        let end = normalizedMinutes(config.quietHoursEndMinutes)

        if start == end {
            return true
        }

        if start < end {
            return currentMinutes >= start && currentMinutes < end
        }

        return currentMinutes >= start || currentMinutes < end
    }

    private func normalizedMinutes(_ minutes: Int) -> Int {
        let dayMinutes = 24 * 60
        let value = minutes % dayMinutes
        return value >= 0 ? value : value + dayMinutes
    }

    private func configureAwayObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAwayState(isAsleep: true, trigger: "screens-sleep")
            }
        }
        workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAwayState(isAsleep: false, trigger: "screens-wake")
            }
        }

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAwayState(isLocked: true, trigger: "screen-locked")
            }
        }
        distributedCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAwayState(isLocked: false, trigger: "screen-unlocked")
            }
        }
    }

    private func updateAwayState(isLocked: Bool? = nil, isAsleep: Bool? = nil, trigger: String) {
        let wasAway = isCurrentlyAway

        if let isLocked {
            isScreenLocked = isLocked
        }
        if let isAsleep {
            isScreenAsleep = isAsleep
        }

        let nowAway = isCurrentlyAway
        logAsync("away state trigger=\(trigger) locked=\(isScreenLocked) asleep=\(isScreenAsleep) away=\(nowAway)")

        if !wasAway, nowAway {
            let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
            awaySessionStart = Date().addingTimeInterval(-idleSeconds)
            clearNotifications(reason: "away-start")
            return
        }

        if wasAway, !nowAway {
            let returnTime = Date()
            let awayStart = awaySessionStart ?? returnTime
            awaySessionStart = nil
            logAsync("away ended trigger=\(trigger) durationSeconds=\(Int(returnTime.timeIntervalSince(awayStart)))")
            scheduleNotifications()
            sendAwayCatchUpSummaryIfNeeded(from: awayStart, to: returnTime)
        }
    }

    private func sendAwayCatchUpSummaryIfNeeded(from start: Date, to end: Date) {
        guard config.awayCatchUpEnabled else {
            logAsync("away summary skipped reason=feature-disabled")
            return
        }
        guard isWithinAwayCatchUpWindow(end) else {
            logAsync("away summary skipped reason=outside-return-window")
            return
        }

        let missedDates = missedTriggerDates(from: start, to: end)
        guard let _ = missedDates.first else {
            logAsync("away summary skipped reason=no-missed-intervals")
            return
        }

        let awaySeconds = Int(end.timeIntervalSince(start))
        let hours = awaySeconds / 3600
        let minutes = (awaySeconds % 3600) / 60
        let duration: String
        if hours > 0, minutes > 0 {
            duration = "\(hours)h \(minutes)m"
        } else if hours > 0 {
            duration = "\(hours)h"
        } else {
            duration = "\(minutes)m"
        }
        let timeRange = "\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))"
        let body = "Away \(duration) (\(timeRange))"

        logAsync("away summary queued duration=\(duration) from=\(start.ISO8601Format()) to=\(end.ISO8601Format())")
        sendNotification(body: body, context: "away-summary")
    }

    private func missedTriggerDates(from start: Date, to end: Date) -> [Date] {
        guard start < end, let first = firstTriggerDate(after: start) else { return [] }

        let interval = max(1, config.intervalMinutes)
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = first

        while current < end {
            if shouldCountAwayMissedInterval(at: current) {
                dates.append(current)
            }

            guard let next = calendar.date(byAdding: .minute, value: interval, to: current) else { break }
            current = next
        }

        return dates
    }

    private func shouldCountAwayMissedInterval(at date: Date) -> Bool {
        guard config.awayCatchUpEnabled else { return false }
        guard isWithinAwayCatchUpWindow(date) else { return false }
        return notificationBlockReason(at: date, respectAwayState: false) == nil
    }

    private func isWithinAwayCatchUpWindow(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        guard config.awayCatchUpWeekdays.contains(weekday) else { return false }

        let currentMinutes = minutesSinceMidnight(for: date)
        let start = normalizedMinutes(config.awayCatchUpStartMinutes)
        let end = normalizedMinutes(config.awayCatchUpEndMinutes)

        if start == end {
            return true
        }

        if start < end {
            return currentMinutes >= start && currentMinutes < end
        }

        return currentMinutes >= start || currentMinutes < end
    }

    private func minutesSinceMidnight(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func refreshStatusUI() {
        enabledMenuItem?.title = config.isEnabled ? "Disable Clocktower" : "Enable Clocktower"

        let symbolName: String
        if !config.isEnabled {
            symbolName = "pause.circle"
        } else if config.quietHoursEnabled, isWithinQuietHours(Date()) {
            symbolName = "moon.circle"
        } else {
            symbolName = "circlebadge"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Clocktower") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        }
        logAsync("status refreshed symbol=\(symbolName) enabled=\(config.isEnabled)")
    }

    private func isLikelyPresenting() -> Bool {
        // Check if any display is mirrored (projector/TV presentation setup)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        for i in 0..<Int(displayCount) {
            if CGDisplayMirrorsDisplay(displayIDs[i]) != kCGNullDirectDisplay { return true }
        }

        // Check if a presentation app is running a fullscreen window (slideshow mode)
        let presentationBundles = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint"]
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  let bundleID = app.bundleIdentifier,
                  presentationBundles.contains(bundleID) else { continue }

            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            if w >= mainBounds.width && h >= mainBounds.height { return true }
        }
        return false
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logAsync("notifications will-present id=\(notification.request.identifier)")
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logAsync("notifications did-receive id=\(response.notification.request.identifier)")
        DispatchQueue.main.async { [weak self] in
            self?.lastNonSelfApp?.activate(options: .activateIgnoringOtherApps)
        }
        completionHandler()
    }
}
