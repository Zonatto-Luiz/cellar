// Draws Cellar's 1024x1024 app icon (wine glass on a burgundy squircle) to the path in argv[1].
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon grid: ~100pt margin, ~185pt corner radius at 1024.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.30, green: 0.04, blue: 0.12, alpha: 1),
])!.draw(in: path, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .regular)
    .applying(.init(paletteColors: [.white]))
if let glass = NSImage(systemSymbolName: "wineglass.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = glass.size
    glass.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
