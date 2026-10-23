import AppKit

let app = URL(fileURLWithPath: CommandLine.arguments[1])
let expected = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/HubIcon.icns"))!
let resolved = NSWorkspace.shared.icon(forFile: app.path)
func pixels(_ image: NSImage) -> [UInt8] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
    NSGraphicsContext.restoreGraphicsState()
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
}
let a = pixels(expected), b = pixels(resolved)
let difference = zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
guard difference < 8 else { fputs("FAIL: macOS resolved a different app icon (difference \(difference))\n", stderr); exit(1) }
print("PASS: macOS resolves bundled application icon (difference \(difference))")
