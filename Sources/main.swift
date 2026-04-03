import AppKit

let singletonStore = ConfigStore()
let singleton = ProcessSingleton()

if !singleton.acquireLock(at: singletonStore.lockURL) {
    logAsync("startup exiting because another instance already holds the singleton lock")
    exit(0)
}

let app = NSApplication.shared
let delegate = BellApp()
logAsync("startup launching Clocktower bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
app.delegate = delegate
app.run()
