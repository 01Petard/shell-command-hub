import AppKit

let png = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))!
guard png.pixelsWide == 512, png.pixelsHigh == 512 else {
    fputs("FAIL: icon PNG must be 512x512\n", stderr)
    exit(1)
}
var minX = 512, minY = 512, maxX = -1, maxY = -1
for y in 0..<512 {
    for x in 0..<512 {
        let color = png.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        if color.alphaComponent > 0.99 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard (39...40).contains(minX), abs((maxX - minX) - (maxY - minY)) <= 1,
      abs(minX + maxX - 511) <= 2, abs(minY + maxY - 511) <= 2 else {
    fputs("FAIL: icon tile must be square and centered with the DevDock inset\n", stderr)
    exit(1)
}
guard png.colorAt(x: 0, y: 0)!.alphaComponent == 0,
      png.colorAt(x: 511, y: 511)!.alphaComponent == 0 else {
    fputs("FAIL: icon corners must be transparent\n", stderr)
    exit(1)
}
print("PASS: 512x512 PNG with centered tile, DevDock inset and transparent corners")

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
