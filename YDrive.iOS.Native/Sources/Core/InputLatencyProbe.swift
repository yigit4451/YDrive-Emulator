import Foundation

/// TEMP diagnostics for the touch → libretro input path.
///
/// Appends timestamped lines to `Documents/input_latency.log` (visible in the Files app
/// because `UIFileSharingEnabled` is on). Stops after `maxLines` lines so it can never grow
/// unbounded. All formatting/IO happens on a private utility queue, never on the touch path.
///
/// Fields:
/// - `hw→app`  : `ProcessInfo.systemUptime - touch.timestamp` when the touch reached our code
///               (time iOS spent delivering the touch; a large value = system/gesture gate delay).
/// - `press→poll`: time between `setButton(pressed: true)` and libretro's next input poll.
enum InputLatencyProbe {
    private static let maxLines = 2000
    private static let queue = DispatchQueue(label: "com.yigit.ydrive.inputprobe", qos: .utility)
    nonisolated(unsafe) private static var lineCount = 0
    nonisolated(unsafe) private static var handle: FileHandle?

    /// Current uptime in ms (same clock as `UITouch.timestamp`).
    static var nowMs: Double { ProcessInfo.processInfo.systemUptime * 1000 }

    static func log(_ message: String) {
        let stamp = nowMs
        queue.async {
            guard lineCount < maxLines else { return }
            if handle == nil {
                let url = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("input_latency.log")
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            lineCount += 1
            let line = String(format: "%.3f %@\n", stamp, message)
            if let data = line.data(using: .utf8) {
                try? handle?.write(contentsOf: data)
            }
        }
    }
}
