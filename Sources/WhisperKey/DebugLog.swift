import Foundation

/// File-based debug log (~/.whisperkey/debug.log), enabled via config.
/// Unified logging redacts dynamic strings as <private>, so a plain file
/// is the only practical way to debug a background app like this.
func debugLog(_ msg: String) {
    guard Config.shared.debugLog else { return }
    let line = "\(Date()) \(msg)\n"
    let path = Config.dir + "/debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        try? FileManager.default.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
