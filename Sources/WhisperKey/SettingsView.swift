import AppKit
import SwiftUI

// MARK: - Model catalog

struct STTModel: Identifiable {
    let id: String        // HuggingFace repo
    let name: String
    let size: String
    let speed: String
    let quality: String
    let note: String?
}

let sttModels: [STTModel] = [
    STTModel(id: "mlx-community/whisper-large-v3-turbo",
             name: "Large v3 Turbo", size: "1.6 GB", speed: "~2 s / phrase",
             quality: "Best multilingual accuracy", note: "Recommended"),
    STTModel(id: "mlx-community/whisper-medium-mlx",
             name: "Medium", size: "1.5 GB", speed: "~3 s / phrase",
             quality: "Good accuracy", note: nil),
    STTModel(id: "mlx-community/whisper-small-mlx",
             name: "Small", size: "0.5 GB", speed: "~1 s / phrase",
             quality: "Okay for English, weaker for other languages", note: nil),
    STTModel(id: "mlx-community/distil-whisper-large-v3",
             name: "Distil Large v3", size: "1.5 GB", speed: "~1.5 s / phrase",
             quality: "Near-large accuracy", note: "English only"),
]

// MARK: - Learning backends

struct LearnBackend: Identifiable {
    let id: String
    let name: String
    let detail: String
    let cliName: String?  // binary to detect; nil = always available
}

let learnBackends: [LearnBackend] = [
    LearnBackend(id: "ollama", name: "Ollama (local LLM)",
                 detail: "Fully local, free. Uses a small model like qwen3:4b.",
                 cliName: "ollama"),
    LearnBackend(id: "claude", name: "Claude Code CLI",
                 detail: "Uses `claude -p` with the Haiku model.", cliName: "claude"),
    LearnBackend(id: "codex", name: "Codex CLI",
                 detail: "Uses `codex exec`.", cliName: "codex"),
    LearnBackend(id: "agent-manual", name: "My own agent (manual)",
                 detail: "Writes a task file you hand to any coding agent (Hermes, OpenClaw, …).",
                 cliName: nil),
    LearnBackend(id: "off", name: "Off",
                 detail: "The glossary stays as you wrote it.", cliName: nil),
]

func cliAvailable(_ name: String?) -> Bool {
    guard let name else { return true }
    let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                NSString(string: "~/.local/bin").expandingTildeInPath,
                NSString(string: "~/bin").expandingTildeInPath]
    return dirs.contains { FileManager.default.fileExists(atPath: "\($0)/\(name)") }
}

// MARK: - Glass card styling

struct GlassCard: ViewModifier {
    var selected: Bool
    func body(content: Content) -> some View {
        let base = content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        // glassEffect exists only in the macOS 26+ SDK — availability checks guard
        // the runtime, not the compiler, so older SDKs (CI runners) need #if too
        return Group {
            #if compiler(>=6.4)
            if #available(macOS 26.0, *) {
                base.glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                base.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            #else
            base.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            #endif
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .white.opacity(0.08),
                              lineWidth: selected ? 2 : 1)
        )
    }
}

extension View {
    func glassCard(selected: Bool = false) -> some View { modifier(GlassCard(selected: selected)) }
}

// MARK: - Transcription history

struct TranscriptEntry: Identifiable {
    let id: Int
    let ts: Date
    let text: String
    let language: String
}

enum TranscriptHistory {
    static var path: String { Config.shared.serverDir + "/transcripts.jsonl" }

    static func load(limit: Int = 300) -> [TranscriptEntry] {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        let lines = raw.split(separator: "\n").suffix(limit)
        return lines.enumerated().compactMap { i, line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String, !text.isEmpty else { return nil }
            let ts = (json["ts"] as? String).flatMap { iso.date(from: $0) } ?? .distantPast
            return TranscriptEntry(id: i, ts: ts,
                                   text: text,
                                   language: json["language"] as? String ?? "")
        }.reversed()
    }

    static func clear() {
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
    }
}

final class HistoryModel: ObservableObject {
    @Published var entries: [TranscriptEntry] = []
    @Published var copiedID: Int?
    @Published var confirmClear = false
}

struct HistoryView: View {
    // @State is a macro in the macOS 26 SDK and doesn't compile with bare CLT —
    // state lives in an ObservableObject owned by the window controller instead
    @ObservedObject var model: HistoryModel

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dictation history").font(.title3.bold())
                Spacer()
                Button("Refresh") { model.entries = TranscriptHistory.load() }
                Button("Clear…", role: .destructive) { model.confirmClear = true }
                    .confirmationDialog("Delete the entire dictation history?",
                                        isPresented: $model.confirmClear) {
                        Button("Delete all", role: .destructive) {
                            TranscriptHistory.clear()
                            model.entries = []
                        }
                    }
            }
            Text("Stored locally in transcripts.jsonl. Click any entry to copy it.")
                .font(.callout).foregroundStyle(.secondary)

            if model.entries.isEmpty {
                Spacer()
                Text("No dictations yet — hold right ⌘ and say something.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(model.entries) { e in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(e.text, forType: .string)
                        model.copiedID = e.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if model.copiedID == e.id { model.copiedID = nil }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(timeFormatter.string(from: e.ts))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !e.language.isEmpty {
                                    Text(e.language.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                }
                                Spacer()
                                if model.copiedID == e.id {
                                    Text("Copied ✓").font(.caption).foregroundStyle(.green)
                                }
                            }
                            Text(e.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .onAppear { model.entries = TranscriptHistory.load() }
    }
}

// MARK: - Settings view

final class SettingsModel: ObservableObject {
    @Published var config = Config.shared
    @Published var serverStatus = "…"
    @Published var selectedTranscriptionBackend = Config.shared.transcriptionBackend
    @Published var cloudAPIKey = ""
    @Published var hasCloudAPIKey = false
    @Published var cloudValidationError: String?
    var onActivate: (() -> Void)?

    func save(restartServer: Bool = false) {
        if restartServer {
            config.save()
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)/restart")!)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        } else {
            // Backend controls are drafts until their explicit activation button.
            var persisted = config
            persisted.model = Config.shared.model
            persisted.transcriptionBackend = Config.shared.transcriptionBackend
            persisted.cloudProvider = Config.shared.cloudProvider
            persisted.cloudEndpoint = Config.shared.cloudEndpoint
            persisted.cloudModel = Config.shared.cloudModel
            persisted.save()
        }
    }

    func selectCloudProvider(_ provider: String) {
        config.cloudProvider = provider
        if provider == "groq" {
            config.cloudEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
            config.cloudModel = "whisper-large-v3-turbo"
        }
        cloudValidationError = nil
    }

    func activateLocal() {
        selectedTranscriptionBackend = "local"
        config.transcriptionBackend = "local"
        config.setupComplete = true
        cloudValidationError = nil
        serverStatus = "starting…"
        save(restartServer: true)
        onActivate?()
        pollHealthSoon()
    }

    func activateCloud() {
        let endpoint = config.cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.cloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredKey = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateCloudEndpoint(endpoint) else {
            cloudValidationError = "Enter a full HTTPS transcription endpoint (HTTP is allowed only for localhost)."
            return
        }
        guard !model.isEmpty else {
            cloudValidationError = "Enter a cloud transcription model."
            return
        }
        guard enteredKey.rangeOfCharacter(from: .controlCharacters) == nil else {
            cloudValidationError = "The API key contains invalid control characters."
            return
        }
        do {
            if !enteredKey.isEmpty {
                try CloudAPIKeyStore.save(enteredKey)
            } else if try CloudAPIKeyStore.load() == nil {
                cloudValidationError = "Enter an API key. It will be stored in macOS Keychain."
                return
            }
            hasCloudAPIKey = true
        } catch {
            cloudValidationError = "Could not save the API key in Keychain: \(error.localizedDescription)"
            return
        }

        config.cloudEndpoint = endpoint
        config.cloudModel = model
        selectedTranscriptionBackend = "openai"
        config.transcriptionBackend = "openai"
        config.setupComplete = true
        cloudAPIKey = ""
        cloudValidationError = nil
        serverStatus = "starting…"
        save(restartServer: true)
        TranscriptionNotifier.requestPermission()
        onActivate?()
        pollHealthSoon()
    }

    func deleteCloudAPIKey() {
        do {
            try CloudAPIKeyStore.delete()
            cloudAPIKey = ""
            hasCloudAPIKey = false
            cloudValidationError = nil
        } catch {
            cloudValidationError = "Could not delete the Keychain API key: \(error.localizedDescription)"
        }
    }

    func reloadCloudAPIKeyState() {
        do {
            hasCloudAPIKey = try CloudAPIKeyStore.load() != nil
        } catch {
            hasCloudAPIKey = false
            cloudValidationError = "Could not read the Keychain API key: \(error.localizedDescription)"
        }
    }

    func pollHealth() {
        let url = URL(string: "http://127.0.0.1:\(config.port)/health")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var status = "server offline"
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["status"] as? String {
                switch value {
                case "ok": status = "ready"
                case "loading": status = "loading model…"
                default: status = json["error"] as? String ?? "configuration error"
                }
            }
            DispatchQueue.main.async { self.serverStatus = status }
        }.resume()
    }

    private func pollHealthSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.pollHealth() }
    }

    private func validateCloudEndpoint(_ value: String) -> Bool {
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(),
              !host.isEmpty, !parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              scheme == "https" || scheme == "http" else { return false }
        if scheme == "http" {
            return ["localhost", "127.0.0.1", "::1"].contains(host)
        }
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let isFirstRun: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isFirstRun {
                    Text("Welcome to WhisperKey")
                        .font(.largeTitle.bold())
                    Text("Hold or tap the right ⌘ key to dictate anywhere. Choose local or cloud speech-to-text and how the glossary should learn — you can change everything here later.")
                        .foregroundStyle(.secondary)
                }

                section("Speech-to-text", subtitle: "Server: \(model.serverStatus). Choose where your audio is transcribed.") {
                    HStack(spacing: 10) {
                        Button {
                            model.selectedTranscriptionBackend = "local"
                            model.cloudValidationError = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Local MLX").font(.headline)
                                Text("Private · Apple Silicon GPU")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .glassCard(selected: model.selectedTranscriptionBackend == "local")

                        Button {
                            model.selectedTranscriptionBackend = "openai"
                            model.cloudValidationError = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cloud API").font(.headline)
                                Text("OpenAI-compatible endpoint")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .glassCard(selected: model.selectedTranscriptionBackend == "openai")
                    }

                    if model.selectedTranscriptionBackend == "local" {
                        ForEach(sttModels) { m in
                            Button { model.config.model = m.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(m.name).font(.headline)
                                            if let note = m.note {
                                                Text(note).font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Capsule().fill(note == "Recommended" ? Color.accentColor.opacity(0.25) : Color.orange.opacity(0.25)))
                                            }
                                        }
                                        Text("\(m.size) · \(m.speed) · \(m.quality)")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.config.model == m.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .glassCard(selected: model.config.model == m.id)
                        }
                        Button("Save & Use Local STT") { model.activateLocal() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        HStack(spacing: 10) {
                            Button { model.selectCloudProvider("groq") } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Groq").font(.headline)
                                    Text("Preset").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .glassCard(selected: model.config.cloudProvider == "groq")

                            Button { model.selectCloudProvider("custom") } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Custom").font(.headline)
                                    Text("Your endpoint")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .glassCard(selected: model.config.cloudProvider == "custom")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Endpoint").frame(width: 72, alignment: .leading)
                                TextField("https://…/audio/transcriptions", text: Binding(
                                    get: { model.config.cloudEndpoint },
                                    set: { model.config.cloudEndpoint = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(model.config.cloudProvider == "groq")
                            }
                            HStack {
                                Text("Model").frame(width: 72, alignment: .leading)
                                TextField("whisper-large-v3-turbo", text: Binding(
                                    get: { model.config.cloudModel },
                                    set: { model.config.cloudModel = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("API key").frame(width: 72, alignment: .leading)
                                SecureField(model.hasCloudAPIKey ? "Saved — enter to replace" : "Required", text: $model.cloudAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                if model.hasCloudAPIKey {
                                    Button("Delete") { model.deleteCloudAPIKey() }
                                }
                            }
                            if model.hasCloudAPIKey {
                                Text("API key saved in macOS Keychain.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .glassCard()

                        if let error = model.cloudValidationError {
                            Text(error).font(.callout).foregroundStyle(.red)
                        }
                        Button("Save & Use Cloud STT") { model.activateCloud() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                section("Glossary self-learning", subtitle: "Reviews your recent dictations and teaches the glossary new domain terms.") {
                    ForEach(learnBackends) { b in
                        let available = cliAvailable(b.cliName)
                        Button {
                            guard available else { return }
                            model.config.learnBackend = b.id
                            model.save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.name).font(.headline)
                                        .foregroundStyle(available ? .primary : .secondary)
                                    Text(available ? b.detail : "\(b.cliName ?? "") not found — install it first")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.config.learnBackend == b.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .glassCard(selected: model.config.learnBackend == b.id)
                        .opacity(available ? 1 : 0.55)
                    }
                    if model.config.learnBackend == "ollama" {
                        HStack {
                            Text("Ollama model")
                            TextField("qwen3:4b", text: Binding(
                                get: { model.config.ollamaModel },
                                set: { model.config.ollamaModel = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                            Button("Save") { model.save() }
                        }
                        .padding(.top, 4)
                    }
                }

                section("Hotkey", subtitle: "Right ⌘: tap to toggle recording, hold to push-to-talk.") {
                    HStack {
                        Text("Hold threshold")
                        Slider(value: Binding(
                            get: { model.config.holdThreshold },
                            set: { model.config.holdThreshold = $0 }),
                            in: 0.2...0.6, step: 0.05) { editing in
                            if !editing { model.save() }
                        }
                        Text(String(format: "%.2f s", model.config.holdThreshold))
                            .monospacedDigit().frame(width: 55, alignment: .trailing)
                    }
                    .glassCard()
                }

                section("Privacy", subtitle: nil) {
                    Toggle("Keep a local log of transcriptions (required for self-learning)", isOn: Binding(
                        get: { model.config.logTranscripts },
                        set: { model.config.logTranscripts = $0; model.save() }))
                    Toggle("Debug log (~/.whisperkey/debug.log)", isOn: Binding(
                        get: { model.config.debugLog },
                        set: { model.config.debugLog = $0; model.save() }))
                }

                if model.selectedTranscriptionBackend == "openai" {
                    Text("Cloud mode sends recorded audio and glossary prompt terms to your configured provider. The API key is stored in macOS Keychain.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Local STT runs on this Mac. Audio and text stay local unless you pick a cloud-backed CLI for glossary learning.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: isFirstRun ? 680 : 620)
        .onAppear {
            model.reloadCloudAPIKeyState()
            model.pollHealth()
        }
    }

    @ViewBuilder
    private func section(_ title: String, subtitle: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content()
        }
    }
}

// MARK: - Root tabs

final class SettingsTabState: ObservableObject {
    @Published var tab: Int = 0   // 0 = settings, 1 = history
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var tabs: SettingsTabState
    let history: HistoryModel
    let isFirstRun: Bool

    var body: some View {
        TabView(selection: $tabs.tab) {
            SettingsView(model: model, isFirstRun: isFirstRun)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(0)
            HistoryView(model: history)
                .frame(width: 520, height: 560)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
        }
    }
}

// MARK: - Window controller

final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel
    private let tabs = SettingsTabState()
    private let history = HistoryModel()

    init(onActivate: @escaping () -> Void = {}) {
        model = SettingsModel()
        model.onActivate = onActivate
    }

    func show(firstRun: Bool = false, historyTab: Bool = false) {
        model.config = Config.shared
        model.selectedTranscriptionBackend = model.config.transcriptionBackend
        model.reloadCloudAPIKeyState()
        model.pollHealth()
        tabs.tab = historyTab ? 1 : 0
        history.entries = TranscriptHistory.load()
        if window == nil {
            let view = SettingsRootView(model: model, tabs: tabs, history: history, isFirstRun: firstRun)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "WhisperKey"
            w.titlebarAppearsTransparent = true
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
