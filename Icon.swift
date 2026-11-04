import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: Double(pixels)/1024, y: Double(pixels)/1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(calibratedRed: 0.85, green: 0.94, blue: 0.91, alpha: 1), ending: NSColor(calibratedRed: 0.57, green: 0.80, blue: 0.72, alpha: 1))!.draw(in: tile, angle: -60)
        let door = NSBezierPath()
        door.move(to: NSPoint(x: 350, y: 290)); door.line(to: NSPoint(x: 350, y: 565))
        door.curve(to: NSPoint(x: 512, y: 730), controlPoint1: NSPoint(x: 350, y: 664), controlPoint2: NSPoint(x: 414, y: 730))
        door.curve(to: NSPoint(x: 674, y: 565), controlPoint1: NSPoint(x: 610, y: 730), controlPoint2: NSPoint(x: 674, y: 664))
        door.line(to: NSPoint(x: 674, y: 290)); door.close()
        NSGradient(starting: NSColor(calibratedRed: 0.00, green: 0.31, blue: 0.21, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.64, blue: 0.44, alpha: 1))!.draw(in: door, angle: 0)
        let light = NSBezierPath(); light.move(to: NSPoint(x: 510, y: 290)); light.line(to: NSPoint(x: 510, y: 650)); light.curve(to: NSPoint(x: 674, y: 565), controlPoint1: NSPoint(x: 564, y: 730), controlPoint2: NSPoint(x: 674, y: 680)); light.line(to: NSPoint(x: 674, y: 290)); light.close()
        NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.74, blue: 0.55, alpha: 0.3), ending: NSColor(calibratedRed: 0.65, green: 0.92, blue: 0.76, alpha: 0.9))!.draw(in: light, angle: -90)
        let floor = NSBezierPath(); floor.move(to: NSPoint(x: 240, y: 85)); floor.line(to: NSPoint(x: 495, y: 355)); floor.line(to: NSPoint(x: 570, y: 355)); floor.line(to: NSPoint(x: 795, y: 85)); floor.close()
        NSGradient(starting: NSColor(calibratedRed: 0.88, green: 0.98, blue: 0.90, alpha: 1), ending: NSColor(calibratedRed: 0.43, green: 0.74, blue: 0.63, alpha: 1))!.draw(in: floor, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
