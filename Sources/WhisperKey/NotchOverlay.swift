import AppKit
import SwiftUI

/// Full-screen-safe overlay that visualizes recording state around the MacBook notch,
/// or as a virtual notch on displays without one (e.g. external monitor, lid closed).
final class NotchOverlay {
    enum Mode { case idle, recording, transcribing, inserted }

    private var panel: NSPanel?
    private let model = NotchViewModel()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildPanel()
        }
        rebuildPanel()
    }

    /// Voice loudness (0...1) — drives glow intensity while recording.
    func set(level: Double) {
        model.level = level
    }

    func set(mode: Mode) {
        debugLog("set(\(mode)) panel=\(panel == nil ? "nil" : "ok") visible=\(panel?.isVisible ?? false)")
        model.mode = mode
        guard let panel else { return }
        switch mode {
        case .idle:
            // let the fade-out animation play, then hide the window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.model.mode == .idle { self?.panel?.orderOut(nil) }
            }
        case .inserted:
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.model.mode == .inserted { self?.set(mode: .idle) }
            }
        default:
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Geometry

    /// Notch dimensions of the given screen, or a virtual-notch size if it has none.
    private static func notchSize(for screen: NSScreen) -> (size: CGSize, hasNotch: Bool) {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0 {
            var width: CGFloat = 200
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                width = screen.frame.width - left.width - right.width
            }
            return (CGSize(width: width, height: topInset), true)
        }
        // virtual notch on displays without one — proportions of the real thing
        return (CGSize(width: 200, height: 32), false)
    }

    private func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let (notch, hasNotch) = Self.notchSize(for: screen)
        // capsule is 5% larger than the notch; generous margin so the glow fades
        // to zero well before the window edge (otherwise it clips into a visible
        // hard-cornered rectangle)
        let capsule = CGSize(width: notch.width * 1.05, height: notch.height * 1.05)
        let glowMargin: CGFloat = 80
        let winSize = CGSize(width: capsule.width + glowMargin * 2,
                             height: capsule.height + glowMargin)

        // top-center, flush with the screen's top edge
        let frame = NSRect(
            x: screen.frame.midX - winSize.width / 2,
            y: screen.frame.maxY - winSize.height,
            width: winSize.width,
            height: winSize.height
        )

        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false

        model.capsuleSize = capsule
        model.hasRealNotch = hasNotch
        p.contentView = NSHostingView(rootView: NotchView(model: model))

        panel = p
        debugLog("rebuildPanel frame=\(frame) hasNotch=\(hasNotch)")
        if model.mode != .idle { p.orderFrontRegardless() }
    }
}

// MARK: - SwiftUI

final class NotchViewModel: ObservableObject {
    @Published var mode: NotchOverlay.Mode = .idle
    @Published var capsuleSize: CGSize = .init(width: 220, height: 35)
    @Published var hasRealNotch = false
    @Published var level: Double = 0   // 0...1 voice loudness while recording
}

struct NotchView: View {
    @ObservedObject var model: NotchViewModel

    private var colors: [Color] {
        switch model.mode {
        case .recording:
            return [.red, .orange, .pink, Color(red: 1, green: 0, blue: 0.6), .orange, .red]
        case .transcribing:
            return [.blue, .purple, .cyan, .indigo, .purple, .blue]
        case .inserted:
            return [.green, .mint, .teal, .green, .mint, .green]
        case .idle:
            return [.clear]
        }
    }

    var body: some View {
        // bottom-rounded rectangle hugging the top screen edge, like the notch itself
        // squarer than a capsule, with Apple's continuous (superellipse) curvature —
        // matches the real notch, whose corners ease in and out rather than arc
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: model.capsuleSize.height * 0.34,
                               bottomTrailing: model.capsuleSize.height * 0.34),
            style: .continuous
        )
        ZStack(alignment: .top) {
            Color.clear
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.mode == .idle)) { context in
                // gradient angle derived from frame time — no @State needed
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: 3.0) / 3.0) * 360
                ZStack {
                    if model.mode != .idle {
                        // Apple Intelligence-style glow: the whole capsule is a flowing
                        // gradient; behind a real notch only a soft halo peeks out.
                        // Palette switches are instant (colors aren't animated) while
                        // the angle keeps flowing from the timeline — sharp color
                        // change, uninterrupted shimmer.
                        // Glow = blurred copies of the SHAPE only (no .shadow: shadows
                        // rasterize the layer's rectangular bounds and show up as a
                        // hard-cornered box on dark backgrounds).
                        // while recording the glow breathes with voice loudness;
                        // other modes run at a steady mid intensity
                        let intensity = model.mode == .recording ? 0.35 + 0.65 * model.level : 0.8
                        let gradient = AngularGradient(colors: colors,
                                                       center: .center,
                                                       angle: .degrees(angle))
                        shape.fill(gradient)
                            .blur(radius: 28)
                            .opacity(0.9 * intensity)
                            .scaleEffect(1 + 0.10 * intensity)
                        shape.fill(gradient)
                            .blur(radius: 12)
                            .opacity(0.6 + 0.4 * intensity)
                        shape.fill(gradient)
                            .blur(radius: 2)
                    }
                }
            }
            .frame(width: model.capsuleSize.width, height: model.capsuleSize.height)
            .opacity(model.mode == .idle ? 0 : 1)
            .animation(.easeOut(duration: 0.35), value: model.mode == .idle)
            .animation(.easeOut(duration: 0.12), value: model.level)
        }
    }
}
