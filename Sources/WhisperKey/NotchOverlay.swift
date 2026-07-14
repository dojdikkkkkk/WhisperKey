import AppKit
import SwiftUI

/// Full-screen-safe overlay that visualizes recording state around the MacBook notch,
/// or as a virtual notch on displays without one (e.g. external monitor, lid closed).
final class NotchOverlay {
    enum Mode { case idle, recording, transcribing, inserted }

    private var panels: [NSPanel] = []
    private let model = NotchViewModel()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildPanels()
        }
        rebuildPanels()
    }

    /// Voice loudness (0...1) — drives glow intensity while recording.
    func set(level: Double) {
        model.level = level
    }

    func set(mode: Mode) {
        debugLog("set(\(mode)) panels=\(panels.count)")
        model.mode = mode
        switch mode {
        case .idle:
            // let the fade-out animation play, then hide the windows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.model.mode == .idle else { return }
                self.panels.forEach { $0.orderOut(nil) }
            }
        case .inserted:
            panels.forEach { $0.orderFrontRegardless() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.model.mode == .inserted { self?.set(mode: .idle) }
            }
        default:
            panels.forEach { $0.orderFrontRegardless() }
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
        return (CGSize(width: 210, height: 34), false)
    }

    /// True when this screen is part of a mirror set: an external display shows the
    /// same framebuffer, so pixels "hidden" behind the physical notch are fully
    /// visible there — the notch-hugging style would render as a weird filled bar.
    private static func isMirrored(_ screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsInMirrorSet(id) != 0
    }

    /// One overlay panel per screen: glow behind the real notch on the built-in
    /// display, a dynamic-island indicator on every screen without one.
    private func rebuildPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = []

        for screen in NSScreen.screens {
            let (notch, hasNotch) = Self.notchSize(for: screen)
            // mirrored built-in: the external copy shows the notch-hidden pixels,
            // so fall back to the island style that looks right on both
            let useNotchStyle = hasNotch && !Self.isMirrored(screen)
            // capsule is 5% larger than the notch; the window covers the WHOLE
            // screen so the blurred halo always fades out naturally — a smaller
            // window clips the glow into a hard-edged rectangle at high intensity
            let capsule = CGSize(width: notch.width * 1.05, height: notch.height * 1.05)

            let p = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .screenSaver
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(
                rootView: NotchView(model: model, capsuleSize: capsule, hasRealNotch: useNotchStyle))

            panels.append(p)
            debugLog("rebuildPanels screen=\(screen.localizedName) frame=\(screen.frame) notchStyle=\(useNotchStyle)")
            if model.mode != .idle { p.orderFrontRegardless() }
        }
    }
}

// MARK: - SwiftUI

final class NotchViewModel: ObservableObject {
    @Published var mode: NotchOverlay.Mode = .idle
    @Published var level: Double = 0   // 0...1 voice loudness while recording
}

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    // per-screen constants — each display gets its own panel and style
    let capsuleSize: CGSize
    let hasRealNotch: Bool

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
        if hasRealNotch {
            realNotchGlow
        } else {
            virtualIsland
        }
    }

    /// Built-in display: the capsule hides behind the physical notch,
    /// only the flowing halo peeks out around its edges.
    private var realNotchGlow: some View {
        // bottom-rounded rectangle hugging the top screen edge, like the notch itself
        // squarer than a capsule, with Apple's continuous (superellipse) curvature —
        // matches the real notch, whose corners ease in and out rather than arc
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: capsuleSize.height * 0.34,
                               bottomTrailing: capsuleSize.height * 0.34),
            style: .continuous
        )
        return ZStack(alignment: .top) {
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
                        // recording baseline matches the steady transcribing/inserted
                        // glow (0.8); the voice pushes it ABOVE that — the halo swells
                        // and brightens beyond the resting state on every word
                        let intensity = model.mode == .recording ? 0.8 + 0.8 * model.level : 0.8
                        let gradient = AngularGradient(colors: colors,
                                                       center: .center,
                                                       angle: .degrees(angle))
                        shape.fill(gradient)
                            .blur(radius: 30)
                            .opacity(min(1, intensity))
                            .scaleEffect(1 + 0.25 * intensity)
                        shape.fill(gradient)
                            .blur(radius: 12)
                            .opacity(min(1, 0.25 + 0.75 * intensity))
                            .scaleEffect(1 + 0.10 * max(0, intensity - 0.8))
                        shape.fill(gradient)
                            .blur(radius: 2)
                            .opacity(min(1, 0.45 + 0.55 * intensity))
                    }
                }
            }
            .frame(width: capsuleSize.width, height: capsuleSize.height)
            .opacity(model.mode == .idle ? 0 : 1)
            .animation(.easeOut(duration: 0.35), value: model.mode == .idle)
            .animation(.easeOut(duration: 0.12), value: model.level)
        }
    }

    /// Displays without a notch (external monitors; the pattern for future
    /// Windows/Linux ports): a dynamic-island-style black pill with a live
    /// equalizer dancing to the voice, wrapped in the same soft halo.
    private var virtualIsland: some View {
        let w = capsuleSize.width
        let h = capsuleSize.height
        let pill = UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: h * 0.45, bottomTrailing: h * 0.45),
            style: .continuous
        )
        return ZStack(alignment: .top) {
            Color.clear
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.mode == .idle)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: 3.0) / 3.0) * 360
                let gradient = AngularGradient(colors: colors, center: .center, angle: .degrees(angle))
                let barGradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                let intensity = model.mode == .recording ? 0.55 + 0.45 * model.level : 0.55

                ZStack {
                    if model.mode != .idle {
                        // halo behind the pill — blurred shape copies, never shadows
                        pill.fill(gradient)
                            .blur(radius: 24)
                            .opacity(0.8 * intensity)
                            .scaleEffect(1 + 0.16 * intensity)
                        pill.fill(gradient)
                            .blur(radius: 8)
                            .opacity(0.5 * intensity)

                        // the island itself: black body + thin gradient rim
                        pill.fill(Color.black)
                        pill.strokeBorder(gradient, lineWidth: 1.5)
                            .opacity(0.9)

                        // live equalizer masked by the palette gradient
                        barGradient
                            .mask(EqualizerBars(time: t, level: model.level, mode: model.mode))
                            .padding(.horizontal, w * 0.10)
                            .padding(.top, h * 0.18)
                            .padding(.bottom, h * 0.22)
                    }
                }
            }
            .frame(width: w, height: h)
            .opacity(model.mode == .idle ? 0 : 1)
            .animation(.easeOut(duration: 0.35), value: model.mode == .idle)
            .animation(.easeOut(duration: 0.1), value: model.level)
        }
    }
}

/// Animated equalizer bars. Recording: bars jump with the voice (level scales
/// a per-bar pseudo-random dance). Transcribing: a smooth traveling wave.
/// Inserted: all bars at full height (the green flash reads as "done").
struct EqualizerBars: View {
    let time: TimeInterval
    let level: Double
    let mode: NotchOverlay.Mode

    var body: some View {
        GeometryReader { geo in
            let count = max(8, Int(geo.size.width / 7))
            let barWidth = geo.size.width / CGFloat(count) * 0.55
            let gap = geo.size.width / CGFloat(count) * 0.45
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let h = barHeight(index: i, count: count)
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .frame(width: barWidth, height: max(2, geo.size.height * h))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    private func barHeight(index i: Int, count: Int) -> Double {
        switch mode {
        case .recording:
            // two incommensurate sines per bar ≈ lively pseudo-random dance,
            // amplitude driven by voice loudness
            let dance = abs(sin(time * 6.3 + Double(i) * 1.7)) * 0.6
                      + abs(sin(time * 9.1 + Double(i) * 0.9)) * 0.4
            return 0.12 + (0.15 + 0.85 * level) * dance * 0.88
        case .transcribing:
            // smooth wave traveling across the pill
            let phase = time * 4 - Double(i) * 0.55
            return 0.25 + 0.6 * (0.5 + 0.5 * sin(phase))
        case .inserted:
            return 0.85
        case .idle:
            return 0
        }
    }
}
