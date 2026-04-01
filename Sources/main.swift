import AppKit

let bundleID = Bundle.main.bundleIdentifier ?? "com.clocktower.app"
let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
if running.count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = BellApp()
app.delegate = delegate
app.run()
