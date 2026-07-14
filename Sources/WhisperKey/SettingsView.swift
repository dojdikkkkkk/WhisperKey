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
        return Group {
            if #available(macOS 26.0, *) {
                base.glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                base.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
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

// MARK: - Settings view

final class SettingsModel: ObservableObject {
    @Published var config = Config.shared
    @Published var serverStatus = "…"

    func save(restartServer: Bool = false) {
        config.save()
        if restartServer {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)/restart")!)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        }
    }

    func pollHealth() {
        let url = URL(string: "http://127.0.0.1:\(config.port)/health")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var status = "server offline"
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = json["status"] as? String {
                status = s == "ok" ? "ready" : "loading model…"
            }
            DispatchQueue.main.async { self.serverStatus = status }
        }.resume()
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
                    Text("Hold or tap the right ⌘ key to dictate anywhere. Pick a speech model and how the glossary should learn — you can change everything here later.")
                        .foregroundStyle(.secondary)
                }

                section("Speech model", subtitle: "Server: \(model.serverStatus). Downloaded on first use, runs on the GPU.") {
                    ForEach(sttModels) { m in
                        Button {
                            model.config.model = m.id
                            model.save(restartServer: true)
                        } label: {
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

                Text("Everything runs on this Mac. Audio and text never leave it (unless you pick a cloud-backed CLI for learning).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 520, height: isFirstRun ? 680 : 620)
        .onAppear { model.pollHealth() }
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

// MARK: - Window controller

final class SettingsWindowController {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show(firstRun: Bool = false) {
        model.config = Config.shared
        model.pollHealth()
        if window == nil {
            let view = SettingsView(model: model, isFirstRun: firstRun)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "WhisperKey Settings"
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
