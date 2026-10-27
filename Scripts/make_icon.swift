// Renders the Clipboard Craft app icon into an .iconset folder.
// Usage: swift Scripts/make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with continuous corners.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    path.addClip()
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.27, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.48, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.80, blue: 0.93, alpha: 1)
    ], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    bg.draw(in: body, angle: -60)

    // Soft glow blobs.
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
    glow.draw(fromCenter: CGPoint(x: body.minX + body.width * 0.25, y: body.maxY - body.height * 0.15), radius: 0,
              toCenter: CGPoint(x: body.minX + body.width * 0.25, y: body.maxY - body.height * 0.15), radius: body.width * 0.6, options: [])
    let pinkGlow = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.45, blue: 0.85, alpha: 0.45), NSColor(srgbRed: 1, green: 0.45, blue: 0.85, alpha: 0)])!
    pinkGlow.draw(fromCenter: CGPoint(x: body.maxX - body.width * 0.1, y: body.minY + body.height * 0.1), radius: 0,
                  toCenter: CGPoint(x: body.maxX - body.width * 0.1, y: body.minY + body.height * 0.1), radius: body.width * 0.55, options: [])

    // Back card (a "previous clip").
    let cardW = body.width * 0.50, cardH = body.height * 0.60
    let back = CGRect(x: body.midX - cardW / 2 + body.width * 0.07, y: body.midY - cardH / 2 + body.height * 0.035, width: cardW, height: cardH)
    ctx.saveGState()
    ctx.translateBy(x: back.midX, y: back.midY)
    ctx.rotate(by: -0.14)
    ctx.translateBy(x: -back.midX, y: -back.midY)
    NSColor.white.withAlphaComponent(0.32).setFill()
    NSBezierPath(roundedRect: back, xRadius: cardW * 0.14, yRadius: cardW * 0.14).fill()
    ctx.restoreGState()

    // Front glass card.
    let front = CGRect(x: body.midX - cardW / 2 - body.width * 0.04, y: body.midY - cardH / 2 - body.height * 0.03, width: cardW, height: cardH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.4, alpha: 0.35).cgColor)
    let frontPath = NSBezierPath(roundedRect: front, xRadius: cardW * 0.14, yRadius: cardW * 0.14)
    NSColor.white.withAlphaComponent(0.95).setFill()
    frontPath.fill()
    ctx.restoreGState()

    // Clip at the top of the card.
    let clipW = cardW * 0.42, clipH = cardH * 0.13
    let clip = CGRect(x: front.midX - clipW / 2, y: front.maxY - clipH * 0.55, width: clipW, height: clipH)
    NSColor(srgbRed: 0.24, green: 0.30, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: clipH * 0.45, yRadius: clipH * 0.45).fill()

    // Content lines + a color dot + image tile, hinting at the content types.
    let lineColor = NSColor(srgbRed: 0.33, green: 0.38, blue: 0.62, alpha: 0.55)
    let lx = front.minX + cardW * 0.16
    let lineH = cardH * 0.055
    var ly = front.maxY - cardH * 0.30
    for (i, w) in [0.68, 0.52, 0.60].enumerated() {
        (i == 0 ? NSColor(srgbRed: 0.2, green: 0.45, blue: 0.98, alpha: 0.9) : lineColor).setFill()
        NSBezierPath(roundedRect: CGRect(x: lx, y: ly, width: cardW * w, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2).fill()
        ly -= lineH * 2.1
    }
    let tile = CGRect(x: lx, y: front.minY + cardH * 0.12, width: cardW * 0.30, height: cardW * 0.30)
    let tileGrad = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.62, blue: 0.25, alpha: 1), NSColor(srgbRed: 1, green: 0.35, blue: 0.55, alpha: 1)])!
    tileGrad.draw(in: NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.width * 0.22), angle: -45)
    let dotR = cardW * 0.085
    NSColor(srgbRed: 0.12, green: 0.78, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: tile.maxX + cardW * 0.10, y: tile.midY - dotR, width: dotR * 2, height: dotR * 2)).fill()

    // Top sheen.
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    ctx.restoreGState()

    // Hairline edge.
    NSColor.white.withAlphaComponent(0.25).setStroke()
    path.lineWidth = max(1, s / 512)
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = render(base * scale) { try? data.write(to: out.appendingPathComponent(name)) }
    }
}
print("Wrote \(out.path)")
