import AppKit

// Only manage the app bundles explicitly supplied by the development runner.
// Browser native hosts and other projects are not NSRunningApplication matches.
func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
}
func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let operation = arguments.first, arguments.count > 1 else {
    fail("Usage: dev-app stop <managed app paths...> | wait <app path>")
}
let paths = Set(arguments.dropFirst().map(canonical))
func matches(_ app: NSRunningApplication) -> Bool {
    guard let url = app.bundleURL else { return false }
    return paths.contains(canonical(url.path))
}
if operation == "stop" {
    let all = NSRunningApplication.runningApplications(withBundleIdentifier: "pl.tabnax.Tabnax")
    if let other = all.first(where: { !matches($0) }), let path = other.bundleURL?.path {
        fail("Quit the other Tabnax copy at \(path), then press r and Enter to retry.")
    }
    let apps = all.filter(matches)
    let runningPaths = apps.compactMap { $0.bundleURL?.path }
    for app in apps where !app.isTerminated {
        guard app.terminate() else { fail("Tabnax could not quit. Close it, then press r and Enter to retry.") }
    }
    let deadline = Date().addingTimeInterval(5)
    while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard apps.allSatisfy(\.isTerminated) else { fail("Tabnax is still closing. Finish any open dialog, then press r and Enter.") }
    for path in runningPaths { print(path) }
} else if operation == "wait" {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let app = NSWorkspace.shared.runningApplications.first(where: { matches($0) && $0.isFinishedLaunching && !$0.isTerminated }) {
            print("Running Tabnax pid: \(app.processIdentifier)")
            exit(0)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    fail("The rebuilt app did not finish launching.")
} else {
    fail("Unknown operation: \(operation)")
}
