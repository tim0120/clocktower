import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSMenuDelegate {
    private let configStore: ConfigStore
    private let onSave: (BellConfig) -> Void

    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enable Clocktower", target: nil, action: nil)
    private let intervalField = NSTextField()
    private let titleField = NSTextField()
    private let bodyField = NSTextField()
    private let soundPopUp = NSPopUpButton()
    private let suppressCheckbox = NSButton(checkboxWithTitle: "Suppress when presenting", target: nil, action: nil)
    private let quietHoursCheckbox = NSButton(checkboxWithTitle: "Pause reminders on a daily schedule", target: nil, action: nil)
    private let quietHoursStartPicker = NSDatePicker()
    private let quietHoursEndPicker = NSDatePicker()
    private let awayCatchUpCheckbox = NSButton(checkboxWithTitle: "Summarize missed reminders when I return", target: nil, action: nil)
    private let awayCatchUpStartPicker = NSDatePicker()
    private let awayCatchUpEndPicker = NSDatePicker()
    private let awayCatchUpWeekdayButtons: [(value: Int, button: NSButton)] = [
        (2, NSButton(checkboxWithTitle: "Mon", target: nil, action: nil)),
        (3, NSButton(checkboxWithTitle: "Tue", target: nil, action: nil)),
        (4, NSButton(checkboxWithTitle: "Wed", target: nil, action: nil)),
        (5, NSButton(checkboxWithTitle: "Thu", target: nil, action: nil)),
        (6, NSButton(checkboxWithTitle: "Fri", target: nil, action: nil)),
        (7, NSButton(checkboxWithTitle: "Sat", target: nil, action: nil)),
        (1, NSButton(checkboxWithTitle: "Sun", target: nil, action: nil))
    ]

    private static let systemSounds: [String] = {
        let soundsDir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: soundsDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { $0.replacingOccurrences(of: ".aiff", with: "") }
            .sorted()
    }()

    private var previewSound: NSSound?

    init(configStore: ConfigStore, config: BellConfig, onSave: @escaping (BellConfig) -> Void) {
        self.configStore = configStore
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clocktower Preferences"
        window.minSize = NSSize(width: 620, height: 400)
        window.center()
        super.init(window: window)

        buildUI(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(config: BellConfig) {
        enabledCheckbox.state = config.isEnabled ? .on : .off
        intervalField.stringValue = String(config.intervalMinutes)
        titleField.stringValue = config.title
        bodyField.stringValue = config.bodyTemplate
        suppressCheckbox.state = config.suppressWhenPresenting ? .on : .off
        quietHoursCheckbox.state = config.quietHoursEnabled ? .on : .off
        awayCatchUpCheckbox.state = config.awayCatchUpEnabled ? .on : .off

        configureTimePicker(quietHoursStartPicker, minutes: config.quietHoursStartMinutes)
        configureTimePicker(quietHoursEndPicker, minutes: config.quietHoursEndMinutes)
        configureTimePicker(awayCatchUpStartPicker, minutes: config.awayCatchUpStartMinutes)
        configureTimePicker(awayCatchUpEndPicker, minutes: config.awayCatchUpEndMinutes)
        quietHoursCheckbox.target = self
        quietHoursCheckbox.action = #selector(quietHoursToggled)
        awayCatchUpCheckbox.target = self
        awayCatchUpCheckbox.action = #selector(awayCatchUpToggled)

        for weekdayButton in awayCatchUpWeekdayButtons {
            weekdayButton.button.state = config.awayCatchUpWeekdays.contains(weekdayButton.value) ? .on : .off
            weekdayButton.button.font = .systemFont(ofSize: 11)
        }

        soundPopUp.addItem(withTitle: "Default")
        for sound in Self.systemSounds {
            soundPopUp.addItem(withTitle: sound)
        }
        if let soundName = config.soundName, !soundName.isEmpty,
           let index = Self.systemSounds.firstIndex(of: soundName) {
            soundPopUp.selectItem(at: index + 1)
        } else {
            soundPopUp.selectItem(at: 0)
        }
        soundPopUp.menu?.delegate = self

        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 20
        formStack.translatesAutoresizingMaskIntoConstraints = false

        let generalSection = section(
            title: "General",
            detail: "Basic reminder settings for when Clocktower is actively running.",
            views: [
                enabledCheckbox,
                row(label: "Interval (min)", control: intervalField),
                row(label: "Title", control: titleField),
                row(label: "Body", control: bodyField),
                row(label: "Sound", control: soundPopUp),
                suppressCheckbox
            ]
        )

        let quietHoursSection = section(
            title: "Quiet Hours",
            detail: "Clocktower is fully off during this time. Nothing is shown later.",
            views: [
                quietHoursCheckbox,
                row(label: "Quiet from", control: quietHoursStartPicker),
                row(label: "Resume at", control: quietHoursEndPicker)
            ]
        )

        let awayCatchUpSection = section(
            title: "Away Catch-Up",
            detail: "During the selected work window, Clocktower suppresses live reminders while your Mac is locked or asleep and shows one summary when you return. Outside that window, missed reminders are skipped instead of stacking up.",
            views: [
                awayCatchUpCheckbox,
                row(label: "Work days", control: weekdaySelectionView()),
                row(label: "Work from", control: awayCatchUpStartPicker),
                row(label: "Work until", control: awayCatchUpEndPicker)
            ]
        )

        formStack.addArrangedSubview(generalSection)
        formStack.addArrangedSubview(separator())
        formStack.addArrangedSubview(quietHoursSection)
        formStack.addArrangedSubview(separator())
        formStack.addArrangedSubview(awayCatchUpSection)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(formStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let openConfigButton = NSButton(title: "Open JSON", target: self, action: #selector(openConfig))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(openConfigButton)
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(saveButton)

        let contentView = NSView()
        contentView.addSubview(scrollView)
        contentView.addSubview(buttons)
        window?.contentView = contentView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -16),

            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            formStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            formStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 4),
            formStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            formStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            formStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        updateQuietHoursControls()
        updateAwayCatchUpControls()
    }

    private func row(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .left
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        title.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return row
    }

    private func section(title: String, detail: String, views: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let detailLabel = helpText(detail)

        let contentStack = NSStackView(views: views)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10

        let sectionStack = NSStackView(views: [titleLabel, detailLabel, contentStack])
        sectionStack.orientation = .vertical
        sectionStack.alignment = .leading
        sectionStack.spacing = 8
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        return sectionStack
    }

    private func helpText(_ string: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func weekdaySelectionView() -> NSView {
        let stack = NSStackView(views: awayCatchUpWeekdayButtons.map(\.button))
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        return stack
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func openConfig() {
        logAsync("preferences open-json")
        NSWorkspace.shared.open(configStore.configURL)
    }

    @objc private func quietHoursToggled() {
        updateQuietHoursControls()
    }

    @objc private func awayCatchUpToggled() {
        updateAwayCatchUpControls()
    }

    @objc private func save() {
        let interval = max(1, Int(intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30)
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedIndex = soundPopUp.indexOfSelectedItem
        let sound: String? = selectedIndex > 0 ? soundPopUp.titleOfSelectedItem : nil
        let awayCatchUpWeekdays = selectedAwayCatchUpWeekdays()

        let config = BellConfig(
            isEnabled: enabledCheckbox.state == .on,
            intervalMinutes: interval,
            title: title.isEmpty ? BellConfig.default.title : title,
            bodyTemplate: body.isEmpty ? BellConfig.default.bodyTemplate : body,
            soundName: sound,
            suppressWhenPresenting: suppressCheckbox.state == .on,
            quietHoursEnabled: quietHoursCheckbox.state == .on,
            quietHoursStartMinutes: timePickerMinutes(quietHoursStartPicker),
            quietHoursEndMinutes: timePickerMinutes(quietHoursEndPicker),
            awayCatchUpEnabled: awayCatchUpCheckbox.state == .on,
            awayCatchUpStartMinutes: timePickerMinutes(awayCatchUpStartPicker),
            awayCatchUpEndMinutes: timePickerMinutes(awayCatchUpEndPicker),
            awayCatchUpWeekdays: awayCatchUpWeekdays.isEmpty ? BellConfig.default.awayCatchUpWeekdays : awayCatchUpWeekdays
        )

        configStore.save(config)
        logAsync(
            "preferences save isEnabled=\(config.isEnabled) intervalMinutes=\(config.intervalMinutes) quietHoursEnabled=\(config.quietHoursEnabled) quietStart=\(config.quietHoursStartMinutes) quietEnd=\(config.quietHoursEndMinutes) awayCatchUpEnabled=\(config.awayCatchUpEnabled) awayStart=\(config.awayCatchUpStartMinutes) awayEnd=\(config.awayCatchUpEndMinutes) awayWeekdays=\(config.awayCatchUpWeekdays)"
        )
        onSave(config)
        window?.close()
    }

    // MARK: - NSMenuDelegate

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        previewSound?.stop()
        guard let item = item, item.title != "Default" else { return }
        previewSound = NSSound(named: NSSound.Name(item.title))
        previewSound?.play()
    }

    func menuDidClose(_ menu: NSMenu) {
        previewSound?.stop()
        previewSound = nil
    }

    private func configureTimePicker(_ picker: NSDatePicker, minutes: Int) {
        picker.datePickerElements = .hourMinute
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = date(fromMinutes: minutes)
        picker.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateQuietHoursControls() {
        let enabled = quietHoursCheckbox.state == .on
        quietHoursStartPicker.isEnabled = enabled
        quietHoursEndPicker.isEnabled = enabled
        quietHoursStartPicker.alphaValue = enabled ? 1.0 : 0.5
        quietHoursEndPicker.alphaValue = enabled ? 1.0 : 0.5
    }

    private func updateAwayCatchUpControls() {
        let enabled = awayCatchUpCheckbox.state == .on
        awayCatchUpStartPicker.isEnabled = enabled
        awayCatchUpEndPicker.isEnabled = enabled
        awayCatchUpStartPicker.alphaValue = enabled ? 1.0 : 0.5
        awayCatchUpEndPicker.alphaValue = enabled ? 1.0 : 0.5

        for weekdayButton in awayCatchUpWeekdayButtons {
            weekdayButton.button.isEnabled = enabled
            weekdayButton.button.alphaValue = enabled ? 1.0 : 0.5
        }
    }

    private func date(fromMinutes minutes: Int) -> Date {
        let normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: normalized, to: startOfDay) ?? Date()
    }

    private func timePickerMinutes(_ picker: NSDatePicker) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func selectedAwayCatchUpWeekdays() -> [Int] {
        awayCatchUpWeekdayButtons
            .filter { $0.button.state == .on }
            .map(\.value)
            .sorted()
    }
}
