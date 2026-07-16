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

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let inset: CGFloat = 100
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                          width: canvas - inset * 2,
                                          height: canvas - inset * 2),
                      xRadius: 185, yRadius: 185)
NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1).setFill()
bg.fill()

if let symbol = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)) {
    let tinted = symbol.tinted(.white)
    let s = tinted.size
    tinted.draw(in: NSRect(x: (canvas - s.width) / 2, y: (canvas - s.height) / 2,
                           width: s.width, height: s.height))
}

image.unlockFocus()

guard CommandLine.arguments.count > 1,
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error generando icono\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
