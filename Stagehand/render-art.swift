// Renders the app icon and the logo image from Fonts/Yellowtail-Regular.ttf.
// Usage: swift render-art.swift   (run from Stagehand/)
import AppKit
import CoreText

let fontURL = URL(fileURLWithPath: "Fonts/Yellowtail-Regular.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let ink = rgb(0x0C0C0D)
let cream = rgb(0xF4F1EA)
let bandboxAmber = rgb(0xB07A1E)
let toneColors: [CGColor] = [0x5DCAA5, 0xEF9F27, 0xE8615F, 0x9D96F0].map(rgb)  // Clean, Crunch, Heavy, Lead

func line(_ text: String, font: CTFont, color: CGColor, tracking: CGFloat = 0) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

/// The four tone colors as rounded segments, left to right.
func drawStripe(_ ctx: CGContext, in rect: CGRect, gap: CGFloat) {
    let w = (rect.width - gap * 3) / 4
    for (i, color) in toneColors.enumerated() {
        let seg = CGRect(x: rect.minX + CGFloat(i) * (w + gap), y: rect.minY, width: w, height: rect.height)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: seg, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        ctx.fillPath()
    }
}

func render(width: Int, height: Int, to path: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// The icon artwork, a cream "S" over the tone stripe, laid out for a square `tile`.
func drawMonogram(_ ctx: CGContext, in tile: CGRect) {
    let k = tile.width / 1024
    let s = line("S", font: CTFontCreateWithName("Yellowtail-Regular" as CFString, 760 * k, nil), color: cream)
    let glyph = CTLineGetImageBounds(s, ctx)
    let stripe = CGSize(width: 520 * k, height: 34 * k), gap = 46 * k
    // Center the glyph's ink plus the stripe as one block.
    let bottom = tile.minY + (tile.height - (glyph.height + gap + stripe.height)) / 2
    drawStripe(ctx, in: CGRect(x: tile.midX - stripe.width / 2, y: bottom, width: stripe.width, height: stripe.height),
               gap: 26 * k)
    ctx.textPosition = CGPoint(x: tile.midX - glyph.width / 2 - glyph.minX, y: bottom + stripe.height + gap - glyph.minY)
    CTLineDraw(s, ctx)
}

// iPhone icon: stage black to the edges. iOS rounds the corners itself and wants no
// transparency, so the icon is fully opaque.
render(width: 1024, height: 1024, to: "iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png") { ctx in
    ctx.setFillColor(ink)
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawMonogram(ctx, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
}

// Mac icon: macOS draws icons as they are, so this one carries the standard rounded
// square (824 pt with a 100 pt margin on a 1024 canvas). build.sh turns it into an .icns.
render(width: 1024, height: 1024, to: "Art/AppIcon-mac.png") { ctx in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.setFillColor(ink)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.fillPath()
    drawMonogram(ctx, in: tile)
}

// Logo on a transparent background, for the README and anywhere else outside the app.
render(width: 1200, height: 440, to: "Art/logo.png") { ctx in
    let word = line("Stagehand", font: CTFontCreateWithName("Yellowtail-Regular" as CFString, 230, nil), color: ink)
    let kicker = line("BANDBOX", font: NSFont.systemFont(ofSize: 52, weight: .medium) as CTFont,
                      color: bandboxAmber, tracking: 52 * 0.32)
    let w = CTLineGetImageBounds(word, ctx), k = CTLineGetImageBounds(kicker, ctx)
    let stripe = CGSize(width: w.width * 0.7, height: 18)
    let block = k.height + 30 + w.height + 34 + stripe.height
    var y = (440 - block) / 2
    drawStripe(ctx, in: CGRect(x: (1200 - stripe.width) / 2, y: y, width: stripe.width, height: stripe.height), gap: 13)
    y += stripe.height + 34
    ctx.textPosition = CGPoint(x: (1200 - w.width) / 2 - w.minX, y: y - w.minY)
    CTLineDraw(word, ctx)
    y += w.height + 30
    // The tracking adds space after the last letter too; leave it out when centering.
    ctx.textPosition = CGPoint(x: (1200 - k.width + 52 * 0.32) / 2 - k.minX, y: y - k.minY)
    CTLineDraw(kicker, ctx)
}
