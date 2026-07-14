import AppKit

/// Watches the right Command key globally and drives recording.
///
/// Semantics:
///  - Hold right-Cmd (≥ holdThreshold): push-to-talk — record while held, transcribe on release.
///  - Quick tap: toggle — recording keeps going until the next tap.
///  - If another key is pressed while right-Cmd is down (i.e. it was used as a normal
///    modifier, e.g. Cmd+C), the press must NOT trigger or stop dictation.
final class HotkeyMonitor {
    private let onStartRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onCancelRecording: () -> Void

    private enum State {
        case idle
        case pressed(since: Date, wasRecordingBefore: Bool)
        case toggleRecording
    }

    private var state: State = .idle
    private var usedAsModifier = false
    private var monitors: [Any] = []

    /// How long a press must last to count as "hold" rather than "tap".
    private var holdThreshold: TimeInterval { Config.shared.holdThreshold }

    private let rightCommandKeyCode: UInt16 = 54

    init(onStartRecording: @escaping () -> Void,
         onStopRecording: @escaping () -> Void,
         onCancelRecording: @escaping () -> Void) {
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCancelRecording = onCancelRecording
    }

    func start() {
        // flagsChanged fires on both press and release of modifier keys
        let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        // Any regular key pressed while right-Cmd is down marks it as a modifier use
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            guard let self, case .pressed = self.state else { return }
            self.usedAsModifier = true
        }
        monitors = [flagsMonitor, keyMonitor].compactMap { $0 }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == rightCommandKeyCode else { return }
        let isDown = event.modifierFlags.contains(.command)

        if isDown {
            let wasRecording = { if case .toggleRecording = state { return true } else { return false } }()
            state = .pressed(since: Date(), wasRecordingBefore: wasRecording)
            usedAsModifier = false
            if !wasRecording {
                onStartRecording()
            }
        } else {
            guard case .pressed(let since, let wasRecordingBefore) = state else { return }
            let heldDuration = Date().timeIntervalSince(since)
            handleRelease(heldDuration: heldDuration,
                          usedAsModifier: usedAsModifier,
                          wasRecordingBefore: wasRecordingBefore)
        }
    }

    /// Decides what happens when right-Cmd is released.
    ///
    /// Inputs:
    ///  - heldDuration: seconds the key was held
    ///  - usedAsModifier: another key was pressed during the hold (e.g. Cmd+C)
    ///  - wasRecordingBefore: toggle-recording was already active when this press started
    ///
    /// Must end by setting `state` and calling exactly one of:
    ///  - onStopRecording()   — stop and transcribe
    ///  - onCancelRecording() — discard the recording
    ///  - (nothing)           — keep recording (entering toggle mode)
    private func handleRelease(heldDuration: TimeInterval, usedAsModifier: Bool, wasRecordingBefore: Bool) {
        if usedAsModifier {
            if wasRecordingBefore {
                // Cmd+key during an active toggle recording — keep recording as if nothing happened
                state = .toggleRecording
            } else {
                // A normal shortcut like Cmd+C — discard the accidental recording
                state = .idle
                onCancelRecording()
            }
            return
        }
        if wasRecordingBefore || heldDuration >= holdThreshold {
            // Second tap of a toggle, or end of push-to-talk — transcribe
            state = .idle
            onStopRecording()
        } else {
            // Quick tap — enter toggle mode, keep recording until the next tap
            state = .toggleRecording
        }
    }
}
