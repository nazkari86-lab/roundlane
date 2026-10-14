// MPL-2.0. Launch Services bridge only; all exam policy stays in the native runtime.
import AppKit
import Darwin

let runtimeURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Roundlane")
let args = Array(CommandLine.arguments.dropFirst())
func forward(_ arguments: [String]) -> Never {
    let values = ([runtimeURL.path] + arguments).map { strdup($0) }
    var argv = values + [nil]
    argv.withUnsafeMutableBufferPointer { buffer in _ = execv(runtimeURL.path, buffer.baseAddress!) }
    fputs("Cannot launch bundled Roundlane runtime\n", stderr)
    exit(1)
}
// CLI checks and isolated organizer processes never initialize this AppKit bridge.
if !args.isEmpty && args.first != "--document-open-check" { forward(args) }

if args.first == "--document-open-check" && args.count != 2 { exit(2) }

final class LauncherDelegate: NSObject, NSApplicationDelegate {
    var handedOff = false
    var finished = false
    var pending: String?
    let report: String? = args.first == "--document-open-check" && args.count == 2 ? args[1] : nil
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard filenames.count == 1, filenames[0].lowercased().hasSuffix(".roundlane") else {
            sender.reply(toOpenOrPrint: .failure); return
        }
        pending = filenames[0]
        sender.reply(toOpenOrPrint: .success)
        if finished { launch(pending) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        finished = true
        if pending != nil { launch(pending) }
        else if report == nil { DispatchQueue.main.async { if !self.handedOff { self.launch(self.pending) } } }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func launch(_ path: String?) {
        guard !handedOff else { return }
        var arguments = path.map { _ in ["--participant-file"] } ?? []
        if let path { setenv("ROUNDLANE_PARTICIPANT_FILE", path, 1) }
        if let report {
            guard path != nil else { return }
            arguments += ["--preflight-check"]
            let descriptor = open(report, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0, dup2(descriptor, STDOUT_FILENO) >= 0 else { exit(2) }
            close(descriptor)
        }
        handedOff = true
        // Preserve Launch Services' responsible PID. WebKit's networking helper
        // is then owned by the same native runtime PID checked by SEB. A child
        // Process() makes SEB attribute its own helper to this launcher instead.
        // execv also starts the SEB AppKit lifecycle in a clean process image.
        forward(arguments)
    }

}
let app = NSApplication.shared
let delegate = LauncherDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
