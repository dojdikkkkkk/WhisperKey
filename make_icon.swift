import AppKit

// Renders the WhisperKey app icon: dark rounded square with the glowing
// notch capsule (the app's signature visual) and a voice waveform.
func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    let s = size / 1024.0

    // macOS icon grid: rounded square with margins
    let inset = 100 * s
    let bg = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bgPath = CGPath(roundedRect: bg, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // dark background with subtle vertical sheen
    let bgColors = [NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.16, alpha: 1).cgColor,
                    NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.06, alpha: 1).cgColor] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    if let g = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
    }

    // glowing notch capsule, top-center (bottom corners rounded)
    let notchW = 430 * s, notchH = 110 * s
    let notchRect = CGRect(x: (size - notchW) / 2, y: bg.maxY - notchH, width: notchW, height: notchH)
    let r = 40 * s
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: notchRect.minX, y: notchRect.maxY))
    notch.addLine(to: CGPoint(x: notchRect.minX, y: notchRect.minY + r))
    notch.addQuadCurve(to: CGPoint(x: notchRect.minX + r, y: notchRect.minY),
                       control: CGPoint(x: notchRect.minX, y: notchRect.minY))
    notch.addLine(to: CGPoint(x: notchRect.maxX - r, y: notchRect.minY))
    notch.addQuadCurve(to: CGPoint(x: notchRect.maxX, y: notchRect.minY + r),
                       control: CGPoint(x: notchRect.maxX, y: notchRect.minY))
    notch.addLine(to: CGPoint(x: notchRect.maxX, y: notchRect.maxY))
    notch.closeSubpath()

    // glow behind the capsule
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90 * s,
                  color: NSColor(calibratedRed: 1, green: 0.35, blue: 0.35, alpha: 0.95).cgColor)
    ctx.addPath(notch)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // gradient fill of the capsule (recording palette)
    ctx.saveGState()
    ctx.addPath(notch)
    ctx.clip()
    let warm = [NSColor(calibratedRed: 1.0, green: 0.23, blue: 0.19, alpha: 1).cgColor,
                NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.10, alpha: 1).cgColor,
                NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.55, alpha: 1).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: space, colors: warm, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: notchRect.minX, y: 0),
                               end: CGPoint(x: notchRect.maxX, y: 0), options: [])
    }
    ctx.restoreGState()

    // voice waveform bars, center
    let barW = 52 * s
    let gap = 46 * s
    let heights: [CGFloat] = [140, 260, 420, 300, 180].map { $0 * s }
    let totalW = barW * 5 + gap * 4
    var x = (size - totalW) / 2
    let midY = bg.midY - 60 * s
    for h in heights {
        let bar = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
        let path = CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        ctx.fillPath()
        x += barW + gap
    }

    img.unlockFocus()
    return img
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset written")
