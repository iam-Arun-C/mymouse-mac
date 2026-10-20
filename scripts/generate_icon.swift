import AppKit
import CoreGraphics

func renderIcon(size: Int, outputPath: String) {
    let cgSize = CGSize(width: size, height: size)
    let image = NSImage(size: cgSize)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let s = CGFloat(size)

    // 1. macOS Squircle Background
    let inset = s * 0.08
    let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = s * 0.22
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    ctx.saveGState()
    bgPath.addClip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    }

    // Subtle Cyan Glow Center
    let glowColors = [
        CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.35),
        CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.0)
    ] as CFArray
    if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            startRadius: s * 0.04,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            endRadius: s * 0.42,
            options: []
        )
    }
    ctx.restoreGState()

    // Squircle Border
    NSColor(calibratedRed: 0.0, green: 0.8, blue: 1.0, alpha: 0.45).setStroke()
    bgPath.lineWidth = max(1.0, s * 0.015)
    bgPath.stroke()

    // 2. Gaming Mouse Body
    let mw = s * 0.36
    let mh = s * 0.56
    let mx = (s - mw) / 2.0
    let my = (s - mh) / 2.0
    let mouseRect = CGRect(x: mx, y: my, width: mw, height: mh)
    let mousePath = NSBezierPath(roundedRect: mouseRect, xRadius: mw * 0.48, yRadius: mw * 0.48)

    NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.26, alpha: 1.0).setFill()
    mousePath.fill()

    NSColor(calibratedRed: 0.0, green: 0.88, blue: 1.0, alpha: 0.9).setStroke()
    mousePath.lineWidth = max(1.5, s * 0.022)
    mousePath.stroke()

    // 3. Scroll Wheel
    let ww = mw * 0.16
    let wh = mh * 0.20
    let wx = (s - ww) / 2.0
    let wy = my + mh * 0.62
    let wheelPath = NSBezierPath(roundedRect: CGRect(x: wx, y: wy, width: ww, height: wh), xRadius: ww * 0.45, yRadius: ww * 0.45)
    NSColor(calibratedRed: 0.0, green: 0.92, blue: 0.85, alpha: 1.0).setFill()
    wheelPath.fill()

    // 4. Side Forward Button (Top Left Highlighted Emerald)
    let sw = mw * 0.14
    let sh = mh * 0.17
    let sx = mx - sw * 0.55
    let sy1 = my + mh * 0.48
    let sideFwdPath = NSBezierPath(roundedRect: CGRect(x: sx, y: sy1, width: sw, height: sh), xRadius: sw * 0.5, yRadius: sw * 0.5)
    NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.65, alpha: 1.0).setFill()
    sideFwdPath.fill()

    // 5. Side Backward Button (Bottom Left Highlighted Orange)
    let sy2 = my + mh * 0.25
    let sideBackPath = NSBezierPath(roundedRect: CGRect(x: sx, y: sy2, width: sw, height: sh), xRadius: sw * 0.5, yRadius: sw * 0.5)
    NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.2, alpha: 1.0).setFill()
    sideBackPath.fill()

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

    try? pngData.write(to: URL(fileURLWithPath: outputPath))
}

let args = CommandLine.arguments
let iconsetDir = args.count > 1 ? args[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (sz, name) in sizes {
    renderIcon(size: sz, outputPath: "\(iconsetDir)/\(name)")
}
print("Generated iconset successfully.")
