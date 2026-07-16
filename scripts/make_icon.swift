import AppKit

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        return img
    }
}

// Usage: make_icon.swift <output.png> [ios]
// Default draws the macOS icon (inset rounded rect, transparent corners).
// "ios" draws the same design full-bleed: iOS masks the corners itself and
// rejects transparency, so the background must fill the whole canvas.
let ios = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "ios"

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let orange = NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
if ios {
    orange.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
} else {
    let inset: CGFloat = 100
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                              width: canvas - inset * 2,
                                              height: canvas - inset * 2),
                          xRadius: 185, yRadius: 185)
    orange.setFill()
    bg.fill()
}

if let symbol = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: ios ? 640 : 520, weight: .semibold)) {
    let tinted = symbol.tinted(.white)
    let s = tinted.size
    tinted.draw(in: NSRect(x: (canvas - s.width) / 2, y: (canvas - s.height) / 2,
                           width: s.width, height: s.height))
}

image.unlockFocus()

func pngData(_ image: NSImage) -> Data? {
    if ios {
        // App Store rejects iOS icons with an alpha channel: re-render into an
        // opaque RGB bitmap before exporting.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                                         bitsPerSample: 8, samplesPerPixel: 3,
                                         hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .calibratedRGB,
                                         bytesPerRow: Int(canvas) * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count > 1, let png = pngData(image) else {
    FileHandle.standardError.write(Data("error generando icono\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
