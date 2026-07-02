import AppIntents
import SwiftUI
import WidgetKit

@main
struct ClocktowerControlsBundle: WidgetBundle {
    var body: some Widget {
        ClocktowerStatusWidget()
        ClocktowerToggleControl()
    }
}

// Minimal desktop widget. Primarily here because WidgetKit's descriptor
// enumeration is exercised via the widget path; the control rides along.
struct ClocktowerStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.tim0120.clocktower.widget.status",
            provider: ClocktowerStatusProvider()
        ) { entry in
            VStack {
                Image(systemName: entry.isEnabled ? "bell.fill" : "bell.slash")
                Text(entry.isEnabled ? "Chiming" : "Paused")
            }
        }
        .configurationDisplayName("Clocktower")
        .description("Shows whether Clocktower chimes are on.")
        .supportedFamilies([.systemSmall])
    }
}

struct ClocktowerStatusEntry: TimelineEntry {
    let date: Date
    let isEnabled: Bool
}

struct ClocktowerStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClocktowerStatusEntry {
        ClocktowerStatusEntry(date: Date(), isEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClocktowerStatusEntry) -> Void) {
        completion(ClocktowerStatusEntry(date: Date(), isEnabled: ConfigStore().load().isEnabled))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClocktowerStatusEntry>) -> Void) {
        let entry = ClocktowerStatusEntry(date: Date(), isEnabled: ConfigStore().load().isEnabled)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// A button that opens clocktower://toggle rather than a ControlWidgetToggle
// with a custom SetValueIntent: without Xcode's AppIntents metadata extraction
// a custom intent's parameters never populate ("Prepared value to Bool(nil)"),
// so the toggle silently no-ops. OpenURLIntent's metadata ships with the OS,
// and the app flips the state when it receives the URL.
struct ClocktowerToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ClocktowerIntegration.controlKind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "clocktower://toggle")!)) {
                let isEnabled = ConfigStore().load().isEnabled
                Label(
                    isEnabled ? "Clocktower On" : "Clocktower Off",
                    systemImage: isEnabled ? "bell.fill" : "bell.slash"
                )
            }
        }
        .displayName("Clocktower")
        .description("Toggle Clocktower chimes.")
    }
}
