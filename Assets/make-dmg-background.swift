import AppKit

// Generates the DMG installer-window background at 1x and 2x, then combines them
// into a HiDPI-aware background.tiff. Run via `swift Assets/make-dmg-background.swift`.
// Rerun this whenever the look should change; the .tiff is what build.sh ships.

let width: CGFloat = 640
let height: CGFloat = 420

// Icon drop positions must match the Finder icon positions set in build.sh.
let appIconCenter = CGPoint(x: 170, y: 220)
let appsIconCenter = CGPoint(x: 470, y: 220)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pxWidth = Int(width * scale)
    let pxHeight = Int(height * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxWidth, pixelsHigh: pxHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // AppKit's default coordinate origin here is bottom-left; convert the
    // top-left design coordinates below with `flip()`.
    func flipY(_ y: CGFloat) -> CGFloat { height - y }

    // Background: a soft vertical gradient.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.11, alpha: 1),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Title + subtitle near the top.
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    let title = "Laserpoint"
    title.draw(
        in: NSRect(x: 0, y: flipY(70), width: width, height: 34),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: titleStyle,
        ]
    )
    let subtitle = "Drag the app onto the Applications folder to install"
    subtitle.draw(
        in: NSRect(x: 0, y: flipY(104), width: width, height: 20),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
            .paragraphStyle: titleStyle,
        ]
    )

    // Arrow between the two icon slots (icons themselves are drawn by Finder).
    let arrowY = flipY(appIconCenter.y)
    let startX = appIconCenter.x + 70
    let endX = appsIconCenter.x - 70
    let arrowColor = NSColor(white: 1, alpha: 0.35)
    arrowColor.setStroke()
    let shaft = NSBezierPath()
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.move(to: CGPoint(x: startX, y: arrowY))
    shaft.line(to: CGPoint(x: endX, y: arrowY))
    shaft.stroke()
    let head = NSBezierPath()
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: CGPoint(x: endX - 12, y: arrowY + 9))
    head.line(to: CGPoint(x: endX, y: arrowY))
    head.line(to: CGPoint(x: endX - 12, y: arrowY - 9))
    head.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let dir = "Assets"
writePNG(render(scale: 1), to: "\(dir)/dmg-background.png")
writePNG(render(scale: 2), to: "\(dir)/dmg-background@2x.png")
print("wrote dmg-background.png and dmg-background@2x.png")
