import Foundation

/// Shared configuration, stored at ~/.whisperkey/config.json and read by both
/// the Swift app and the Python server. Missing keys fall back to defaults,
/// so the file can be edited freely from the terminal.
struct Config: Codable {
    var serverDir: String
    var port: Int
    var model: String
    var holdThreshold: Double
    var learnBackend: String   // "ollama" | "claude" | "codex" | "agent-manual" | "off"
    var learnEvery: Int
    var ollamaModel: String
    var logTranscripts: Bool
    var debugLog: Bool

    static let dir = NSString(string: "~/.whisperkey").expandingTildeInPath
    static let path = dir + "/config.json"

    static let defaults = Config(
        serverDir: NSString(string: "~/WhisperKey/server").expandingTildeInPath,
        port: 8737,
        model: "mlx-community/whisper-large-v3-turbo",
        holdThreshold: 0.35,
        learnBackend: "off",
        learnEvery: 20,
        ollamaModel: "qwen3:4b",
        logTranscripts: true,
        debugLog: false
    )

    /// True when no config file existed before this launch — the app shows the setup wizard.
    static private(set) var isFirstRun = false

    static var shared: Config = load()

    static func load() -> Config {
        guard let data = FileManager.default.contents(atPath: path) else {
            isFirstRun = true
            return defaults
        }
        // tolerate hand-edited files with missing keys
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return defaults
        }
        var c = defaults
        if let v = json["serverDir"] as? String { c.serverDir = NSString(string: v).expandingTildeInPath }
        if let v = json["port"] as? Int { c.port = v }
        if let v = json["model"] as? String { c.model = v }
        if let v = json["holdThreshold"] as? Double { c.holdThreshold = v }
        if let v = json["learnBackend"] as? String { c.learnBackend = v }
        if let v = json["learnEvery"] as? Int { c.learnEvery = v }
        if let v = json["ollamaModel"] as? String { c.ollamaModel = v }
        if let v = json["logTranscripts"] as? Bool { c.logTranscripts = v }
        if let v = json["debugLog"] as? Bool { c.debugLog = v }
        return c
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: URL(fileURLWithPath: Self.path))
        }
        Config.shared = self
    }
}
