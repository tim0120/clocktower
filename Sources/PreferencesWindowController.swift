import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSMenuDelegate {
    private let configStore: ConfigStore
    private let onSave: (BellConfig) -> Void

    private let intervalField = NSTextField()
    private let titleField = NSTextField()
    private let bodyField = NSTextField()
    private let soundPopUp = NSPopUpButton()
    private let suppressCheckbox = NSButton(checkboxWithTitle: "Suppress when presenting", target: nil, action: nil)

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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clocktower Preferences"
        window.center()
        super.init(window: window)

        buildUI(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(config: BellConfig) {
        intervalField.stringValue = String(config.intervalMinutes)
        titleField.stringValue = config.title
        bodyField.stringValue = config.bodyTemplate
        suppressCheckbox.state = config.suppressWhenPresenting ? .on : .off

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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Interval (min)", control: intervalField))
        stack.addArrangedSubview(row(label: "Title", control: titleField))
        stack.addArrangedSubview(row(label: "Body", control: bodyField))
        stack.addArrangedSubview(row(label: "Sound", control: soundPopUp))
        stack.addArrangedSubview(suppressCheckbox)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let openConfigButton = NSButton(title: "Open JSON", target: self, action: #selector(openConfig))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(openConfigButton)
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttons)

        let contentView = NSView()
        contentView.addSubview(stack)
        window?.contentView = contentView

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func row(label: String, control: NSControl) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline

        title.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return row
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.configURL)
    }

    @objc private func save() {
        let interval = max(1, Int(intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30)
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedIndex = soundPopUp.indexOfSelectedItem
        let sound: String? = selectedIndex > 0 ? soundPopUp.titleOfSelectedItem : nil

        let config = BellConfig(
            intervalMinutes: interval,
            title: title.isEmpty ? BellConfig.default.title : title,
            bodyTemplate: body.isEmpty ? BellConfig.default.bodyTemplate : body,
            soundName: sound,
            suppressWhenPresenting: suppressCheckbox.state == .on
        )

        configStore.save(config)
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
}
