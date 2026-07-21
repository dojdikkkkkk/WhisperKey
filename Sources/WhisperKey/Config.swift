import Foundation

/// Shared configuration, stored at ~/.whisperkey/config.json and read by both
/// the Swift app and the Python server. Missing keys fall back to defaults,
/// so the file can be edited freely from the terminal.
struct Config: Codable {
    var serverDir: String
    var port: Int
    var model: String
    var transcriptionBackend: String   // "local" | "openai"
    var cloudProvider: String           // "groq" | "custom"
    var cloudEndpoint: String
    var cloudModel: String
    var setupComplete: Bool
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
        transcriptionBackend: "local",
        cloudProvider: "groq",
        cloudEndpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
        cloudModel: "whisper-large-v3-turbo",
        setupComplete: true,
        holdThreshold: 0.35,
        learnBackend: "off",
        learnEvery: 20,
        ollamaModel: "qwen3:4b",
        logTranscripts: true,
        debugLog: false
    )

    static var shared: Config = load()

    static func load() -> Config {
        guard let data = FileManager.default.contents(atPath: path) else {
            var c = defaults
            c.setupComplete = false
            return c
        }
        // tolerate hand-edited files with missing keys
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return defaults
        }
        var c = defaults
        if let v = json["serverDir"] as? String { c.serverDir = NSString(string: v).expandingTildeInPath }
        if let v = json["port"] as? Int { c.port = v }
        if let v = json["model"] as? String { c.model = v }
        if let v = json["transcriptionBackend"] as? String { c.transcriptionBackend = v }
        if let v = json["cloudProvider"] as? String { c.cloudProvider = v }
        if let v = json["cloudEndpoint"] as? String { c.cloudEndpoint = v }
        if let v = json["cloudModel"] as? String { c.cloudModel = v }
        // Existing configs predate this flag and are already fully set up.
        if let v = json["setupComplete"] as? Bool { c.setupComplete = v }
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
