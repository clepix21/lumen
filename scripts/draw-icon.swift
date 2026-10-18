// Draws Lumen's app icon: an original glowing turquoise cube on a dark rounded square.
// Usage: swift scripts/draw-icon.swift <output.png> [size]
import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1024
let s = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

// macOS icon grid: the tile is 824/1024 of the canvas, with a 185/1024 corner radius.
let inset = s * 100 / 1024
let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.45))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0.03, 0.06, 0.10)); ctx.fillPath()
ctx.restoreGState()

// Tile background: deep night blue, a little lighter at the top.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.07, 0.13, 0.22), rgb(0.02, 0.04, 0.08)], [0, 1]),
                       start: point(0.5, 0.9), end: point(0.5, 0.1), options: [])
// Halo behind the cube.
ctx.drawRadialGradient(gradient([rgb(0.25, 0.85, 0.95, 0.55), rgb(0.10, 0.55, 0.75, 0.18), rgb(0.05, 0.3, 0.5, 0)], [0, 0.45, 1]),
                       startCenter: point(0.5, 0.5), startRadius: 0, endCenter: point(0.5, 0.5), endRadius: s * 0.42, options: [])
ctx.restoreGState()

// Isometric cube, slightly rounded corners on the outline.
let c = point(0.5, 0.52)              // centre of the front vertical edge's top end
let edge = s * 0.215                  // edge length
let dx = edge * cos(.pi / 6), dy = edge * sin(.pi / 6)
let top = CGPoint(x: c.x, y: c.y + 2 * dy)
let left = CGPoint(x: c.x - dx, y: c.y + dy)
let right = CGPoint(x: c.x + dx, y: c.y + dy)
let bottom = CGPoint(x: c.x, y: c.y - edge)
let bottomLeft = CGPoint(x: left.x, y: left.y - edge)
let bottomRight = CGPoint(x: right.x, y: right.y - edge)

func face(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points); path.closeSubpath()
    return path
}
let topFace = face([c, left, top, right])
let leftFace = face([c, left, bottomLeft, bottom])
let rightFace = face([c, right, bottomRight, bottom])
let outline = face([top, right, bottomRight, bottom, bottomLeft, left])

// Outer glow around the cube.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: s * 0.07, color: rgb(0.35, 0.95, 1.0, 0.85))
ctx.addPath(outline); ctx.setFillColor(rgb(0.20, 0.70, 0.85)); ctx.fillPath()
ctx.restoreGState()

func fill(_ path: CGPath, _ g: CGGradient, from a: CGPoint, to b: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
// Faces: the top is lit from inside, the sides fade to deeper turquoise.
fill(topFace, gradient([rgb(0.88, 1.0, 1.0), rgb(0.45, 0.92, 0.98)], [0, 1]), from: c, to: top)
fill(leftFace, gradient([rgb(0.38, 0.86, 0.96), rgb(0.10, 0.48, 0.70)], [0, 1]), from: c, to: bottomLeft)
fill(rightFace, gradient([rgb(0.30, 0.78, 0.92), rgb(0.07, 0.38, 0.60)], [0, 1]), from: c, to: bottomRight)

// Inner light: a soft bloom where the three faces meet.
ctx.saveGState(); ctx.addPath(outline); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.75), rgb(0.7, 1, 1, 0.25), rgb(0.5, 0.95, 1, 0)], [0, 0.35, 1]),
                       startCenter: CGPoint(x: c.x, y: c.y + dy * 0.4), startRadius: 0,
                       endCenter: CGPoint(x: c.x, y: c.y + dy * 0.4), endRadius: edge * 1.05, options: [])
ctx.restoreGState()

// Crisp edges: bright on the lit side, subtle elsewhere.
ctx.setLineJoin(.round); ctx.setLineCap(.round)
ctx.setLineWidth(s * 0.006)
ctx.setStrokeColor(rgb(0.85, 1, 1, 0.9))
ctx.addLines(between: [left, c, right]); ctx.strokePath()
ctx.addLines(between: [c, bottom]); ctx.strokePath()
ctx.setStrokeColor(rgb(0.75, 1, 1, 0.55))
ctx.addPath(outline); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path) (\(size)×\(size))")
