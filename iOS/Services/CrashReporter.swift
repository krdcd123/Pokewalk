import Foundation
import MachO

/// Saves a crash report to Documents/last-crash.txt so the app can show it on the next launch.
/// (Sideloaded apps have no TestFlight/App Store crash reports.)
enum CrashReporter {
    static let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("last-crash.txt")

    static func install() {
        NSSetUncaughtExceptionHandler { e in
            CrashReporter.write("Uncaught exception: \(e.name.rawValue)\nReason: \(e.reason ?? "-")\n\n"
                                + e.callStackSymbols.joined(separator: "\n"))
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { s in
                CrashReporter.write("Signal \(s) (\(String(cString: strsignal(s))))\n\n"
                                    + Thread.callStackSymbols.joined(separator: "\n"))
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    static func write(_ body: String) {
        let info = Bundle.main.infoDictionary ?? [:]
        let header = """
        PokéWalk \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) · iOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(Date().formatted(date: .abbreviated, time: .standard))
        Image base: \(String(format: "0x%lx", Int(bitPattern: _dyld_get_image_header(0))))

        """
        try? (header + body).write(to: fileURL, atomically: false, encoding: .utf8)
    }

    /// Returns (and clears) the report from the last crash, if any.
    static func takeLastReport() -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return text
    }
}
