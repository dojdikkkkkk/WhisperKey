import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let client = TranscriptionClient()
    private var hotkey: HotkeyMonitor!
    private var overlay: NotchOverlay!
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        overlay = NotchOverlay()
        setStatus(.idle)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Learn from recent dictation", action: #selector(learnNow), keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WhisperKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        if Config.isFirstRun {
            Config.shared.save() // materialize defaults so the server sees them
            settings.show(firstRun: true)
        }

        // Accessibility is required for text delivery (AX insert / event posting).
        // The modifier-key monitor works without it, which masks a missing grant.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        debugLog("launch: AXIsProcessTrusted=\(trusted)")
        if !trusted {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("Microphone access denied") }
        }

        client.ensureServerRunning()

        hotkey = HotkeyMonitor(
            onStartRecording: { [weak self] in self?.startRecording() },
            onStopRecording: { [weak self] in self?.stopAndTranscribe() },
            onCancelRecording: { [weak self] in self?.cancelRecording() }
        )
        hotkey.start()
    }

    private var levelTimer: Timer?

    private func startRecording() {
        do {
            try recorder.start()
            setStatus(.recording)
            // feed voice loudness into the notch glow ~20 times a second
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.overlay.set(level: self.recorder.level)
            }
        } catch {
            NSLog("Recording failed: \(error)")
            setStatus(.idle)
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        overlay.set(level: 0)
    }

    private func stopAndTranscribe() {
        stopLevelTimer()
        guard let wavURL = recorder.stop() else {
            setStatus(.idle)
            return
        }
        setStatus(.transcribing)
        client.transcribe(wavURL: wavURL) { [weak self] text in
            DispatchQueue.main.async {
                if let text, !text.isEmpty {
                    TextInserter.insert(text)
                    self?.setStatus(.inserted)
                } else {
                    self?.setStatus(.idle)
                }
            }
        }
    }

    @objc private func learnNow() {
        client.requestLearn()
    }

    @objc private func openSettings() {
        settings.show()
    }

    private func cancelRecording() {
        stopLevelTimer()
        _ = recorder.stop()
        setStatus(.idle)
    }

    enum Status { case idle, recording, transcribing, inserted }

    private func setStatus(_ status: Status) {
        switch status {
        case .idle:
            statusItem.button?.title = "🎙"
            overlay.set(mode: .idle)
        case .recording:
            statusItem.button?.title = "🔴"
            overlay.set(mode: .recording)
        case .transcribing:
            statusItem.button?.title = "⏳"
            overlay.set(mode: .transcribing)
        case .inserted:
            statusItem.button?.title = "🎙"
            overlay.set(mode: .inserted)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
