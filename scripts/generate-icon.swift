import AppKit

// Native vector artwork: a command window connecting three tools.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = directory.appendingPathComponent("HubIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext; context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // Scale the complete artwork to leave the same 80/1024 inset as DevDock.
    context.translateBy(x: 512, y: 512)
    context.scaleBy(x: 864.0 / 928.0, y: 864.0 / 928.0)
    context.translateBy(x: -512, y: -512)
    let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 208, yRadius: 208)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.47, blue: 0.88, alpha: 1), ending: NSColor(srgbRed: 0.07, green: 0.25, blue: 0.59, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.18).setStroke(); tile.lineWidth = 3; tile.stroke()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    let plate = NSBezierPath(roundedRect: NSRect(x: 191, y: 250, width: 642, height: 524), xRadius: 72, yRadius: 72)
    NSColor.white.withAlphaComponent(0.96).setFill(); plate.fill(); NSGraphicsContext.restoreGraphicsState()
    let blue = NSColor(srgbRed: 0.12, green: 0.34, blue: 0.69, alpha: 1)
    blue.withAlphaComponent(0.14).setFill(); NSBezierPath(roundedRect: NSRect(x: 231, y: 659, width: 562, height: 72), xRadius: 31, yRadius: 31).fill()
    for x in [270, 312, 354] { NSColor(srgbRed: 0.32, green: 0.53, blue: 0.79, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 684, width: 20, height: 20)).fill() }
    blue.setStroke(); let command = NSBezierPath(); command.lineWidth = 42; command.lineCapStyle = .round; command.lineJoinStyle = .round
    command.move(to: NSPoint(x: 303, y: 550)); command.line(to: NSPoint(x: 383, y: 478)); command.line(to: NSPoint(x: 303, y: 406)); command.stroke()
    let bus = NSBezierPath(); bus.lineWidth = 27; bus.lineCapStyle = .round; bus.lineJoinStyle = .round
    bus.move(to: NSPoint(x: 469, y: 478)); bus.line(to: NSPoint(x: 563, y: 478)); bus.line(to: NSPoint(x: 563, y: 566)); bus.line(to: NSPoint(x: 666, y: 566))
    bus.move(to: NSPoint(x: 563, y: 478)); bus.line(to: NSPoint(x: 666, y: 478)); bus.move(to: NSPoint(x: 563, y: 478)); bus.line(to: NSPoint(x: 563, y: 390)); bus.line(to: NSPoint(x: 666, y: 390)); bus.stroke()
    blue.setFill(); for y in [364, 452, 540] { NSBezierPath(roundedRect: NSRect(x: 645, y: y, width: 52, height: 52), xRadius: 16, yRadius: 16).fill() }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(512).write(to: iconset.appendingPathComponent("icon_512x512.png"))
try render(512).write(to: directory.appendingPathComponent("HubIcon.png"))
