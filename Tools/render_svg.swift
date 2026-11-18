// Renders an SVG to an .iconset (or a single PNG). Usage: swift render_svg.swift in.svg out.iconset|out.png
import Cocoa
let args = CommandLine.arguments
guard let img = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else { fatalError("cannot load svg") }
func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let out = URL(fileURLWithPath: args[2])
if out.pathExtension == "png" { try! png(1024).write(to: out); exit(0) }
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! png(s).write(to: out.appendingPathComponent("icon_\(s)x\(s).png"))
    try! png(s * 2).write(to: out.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
