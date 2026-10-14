import AppKit

// Finder supplies the real draggable icons; this image supplies only instructions.
let size = NSSize(width: 680, height: 400)
let image = NSImage(size: size)
image.lockFocusFlipped(true)
NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.98, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 30, y: y, width: 620, height: 42), withAttributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

let teal = NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.40, alpha: 1)
centered("English Compass", y: 40, font: .systemFont(ofSize: 27, weight: .semibold), color: .labelColor)
centered("Drag the app into Applications to install", y: 83,
         font: .systemFont(ofSize: 14), color: .secondaryLabelColor)

teal.withAlphaComponent(0.65).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 302, y: 200))
arrow.line(to: NSPoint(x: 378, y: 200))
arrow.move(to: NSPoint(x: 364, y: 186))
arrow.line(to: NSPoint(x: 378, y: 200))
arrow.line(to: NSPoint(x: 364, y: 214))
arrow.stroke()

centered("After copying, open English Compass from Applications.", y: 327,
         font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
image.unlockFocus()
guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Usage: swift dmg-background.swift OUTPUT.png")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
