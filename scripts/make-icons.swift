#!/usr/bin/env swift
// Draws Quill's icons with CoreGraphics. Run from the repo root: swift scripts/make-icons.swift
// Writes Resources/menubar/quill-<state>{,@2x}.png (template, black on clear), Resources/quill-bubble.png,
// Resources/AppIcon.icns, and Resources/icon-preview.png.
import AppKit
import CoreGraphics

let fm = FileManager.default
let root = fm.currentDirectoryPath
let menubarDir = root + "/Resources/menubar"
try? fm.createDirectory(atPath: menubarDir, withIntermediateDirectories: true)

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true); c.setShouldAntialias(true); c.interpolationQuality = .high
    return c
}
func writePNG(_ img: CGImage, to path: String, pointSize: CGSize? = nil) {
    let rep = NSBitmapImageRep(cgImage: img)
    if let s = pointSize { rep.size = s }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - Feather geometry (local frame: x along the quill, 0 = nib, L = tip; y across)

struct Feather {
    var L: CGFloat, w: CGFloat
    var vane: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.17 * L, y: 0))
        p.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: 0.25 * L, y: 1.5 * w), control2: CGPoint(x: 0.70 * L, y: 1.1 * w))
        p.addCurve(to: CGPoint(x: 0.17 * L, y: 0), control1: CGPoint(x: 0.76 * L, y: -0.55 * w), control2: CGPoint(x: 0.33 * L, y: -1.05 * w))
        p.closeSubpath()
        return p
    }
    func line(_ a: CGFloat, _ b: CGFloat) -> CGPath {
        let p = CGMutablePath(); p.move(to: CGPoint(x: a * L, y: 0)); p.addLine(to: CGPoint(x: b * L, y: 0)); return p
    }
}
func place(_ p: CGPath, at o: CGPoint, angle: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: o.x, y: o.y).rotated(by: angle)
    return p.copy(using: &t)!
}

// MARK: - Menu-bar marks (18x18 unit space, y up, black)

enum State: String, CaseIterable { case idle, listening, writing, held, error }

func drawMark(_ s: State, in c: CGContext) {
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 0, alpha: 1))
    c.setLineCap(.round); c.setLineJoin(.round)
    let small = (s == .held || s == .writing || s == .listening)
    let f = small ? Feather(L: 14.5, w: 2.6) : Feather(L: 16.5, w: 3.0)
    let origin = s == .error ? CGPoint(x: 2.8, y: 3.2) : (small ? CGPoint(x: 3.0, y: 5.0) : CGPoint(x: 2.6, y: 2.6))
    let ang = CGFloat.pi / 4
    let vane = place(f.vane, at: origin, angle: ang)
    let shaft = place(f.line(-0.02, 0.5), at: origin, angle: ang)
    let spineCut = place(f.line(0.2, 0.88), at: origin, angle: ang)
    let nibShaft = place(f.line(-0.02, 0.2), at: origin, angle: ang)

    if s == .idle || s == .error {
        // outline feather
        c.setLineWidth(1.5)
        c.addPath(vane); c.strokePath()
        c.setLineWidth(1.5)
        c.addPath(shaft); c.strokePath()
    } else {
        c.addPath(vane); c.fillPath()
        c.setBlendMode(.clear); c.setLineWidth(1.0)
        c.addPath(spineCut); c.strokePath()
        c.setBlendMode(.normal)
        c.setLineWidth(1.6); c.addPath(nibShaft); c.strokePath()
    }

    switch s {
    case .idle: break
    case .listening:
        // sound arcs, upper-left of the feather
        c.setLineWidth(1.3)
        for r in [CGFloat(3.6), 6.4] {
            c.addArc(center: CGPoint(x: 0.4, y: 17.6), radius: r, startAngle: -.pi/2 + 0.12, endAngle: -0.12, clockwise: false)
            c.strokePath()
        }
    case .writing:
        // the line being written, under the nib
        c.setLineWidth(1.7)
        c.move(to: CGPoint(x: 1.3, y: 1.4)); c.addLine(to: CGPoint(x: 11.2, y: 1.4)); c.strokePath()
        c.fillEllipse(in: CGRect(x: 13.2, y: 0.6, width: 1.7, height: 1.7))
        c.fillEllipse(in: CGRect(x: 15.7, y: 0.6, width: 1.7, height: 1.7))
    case .held:
        // "!" badge, lower right, knocked out of the feather
        let ctr = CGPoint(x: 13.6, y: 4.3)
        c.setBlendMode(.clear); c.fillEllipse(in: CGRect(x: ctr.x - 4.6, y: ctr.y - 4.6, width: 9.2, height: 9.2))
        c.setBlendMode(.normal); c.fillEllipse(in: CGRect(x: ctr.x - 3.7, y: ctr.y - 3.7, width: 7.4, height: 7.4))
        c.setBlendMode(.clear); c.setLineWidth(1.4)
        c.move(to: CGPoint(x: ctr.x, y: ctr.y + 2.2)); c.addLine(to: CGPoint(x: ctr.x, y: ctr.y - 0.3)); c.strokePath()
        c.fillEllipse(in: CGRect(x: ctr.x - 0.75, y: ctr.y - 2.5, width: 1.5, height: 1.5))
        c.setBlendMode(.normal)
    case .error:
        // slash, with a gap cut around it
        let a = CGPoint(x: 2.0, y: 16.0), b = CGPoint(x: 16.0, y: 2.0)
        c.setBlendMode(.clear); c.setLineWidth(4.6); c.setLineCap(.butt)
        c.move(to: a); c.addLine(to: b); c.strokePath()
        c.setBlendMode(.normal); c.setLineCap(.round); c.setLineWidth(1.9)
        c.move(to: a); c.addLine(to: b); c.strokePath()
    }
}

func renderMark(_ s: State, px: Int) -> CGImage {
    let c = makeContext(px, px)
    c.scaleBy(x: CGFloat(px) / 18, y: CGFloat(px) / 18)
    drawMark(s, in: c)
    return c.makeImage()!
}

// The bubble's feather: the same silhouette, filled, plain, drawn large (32 pt at 3x).
func renderBubbleFeather(px: Int) -> CGImage {
    let c = makeContext(px, px)
    c.scaleBy(x: CGFloat(px) / 18, y: CGFloat(px) / 18)
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 0, alpha: 1))
    c.setLineCap(.round)
    let f = Feather(L: 16.5, w: 3.0), origin = CGPoint(x: 2.6, y: 2.6), ang = CGFloat.pi / 4
    c.addPath(place(f.vane, at: origin, angle: ang)); c.fillPath()
    c.setBlendMode(.clear); c.setLineWidth(0.8)
    c.addPath(place(f.line(0.2, 0.88), at: origin, angle: ang)); c.strokePath()
    c.setBlendMode(.normal); c.setLineWidth(1.6)
    c.addPath(place(f.line(-0.02, 0.2), at: origin, angle: ang)); c.strokePath()
    return c.makeImage()!
}
writePNG(renderBubbleFeather(px: 96), to: root + "/Resources/quill-bubble.png", pointSize: CGSize(width: 32, height: 32))

for s in State.allCases {
    writePNG(renderMark(s, px: 18), to: "\(menubarDir)/quill-\(s.rawValue).png", pointSize: CGSize(width: 18, height: 18))
    writePNG(renderMark(s, px: 36), to: "\(menubarDir)/quill-\(s.rawValue)@2x.png", pointSize: CGSize(width: 18, height: 18))
}

// MARK: - App icon (1024 design space)

func drawAppIcon(in c: CGContext) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 824 * 0.225, cornerHeight: 824 * 0.225, transform: nil)
    // shadow
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.38))
    c.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.25, alpha: 1))
    c.addPath(shape); c.fillPath()
    c.restoreGState()
    // gradient background
    c.saveGState()
    c.addPath(shape); c.clip()
    let g = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.20, green: 0.27, blue: 0.52, alpha: 1),
        CGColor(red: 0.09, green: 0.13, blue: 0.30, alpha: 1),
        CGColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 330, y: 924), end: CGPoint(x: 700, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // soft top sheen
    let sheen = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.13), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [.drawsBeforeStartLocation])
    c.restoreGState()
    // inner hairline
    c.saveGState()
    c.addPath(shape); c.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); c.setLineWidth(3); c.strokePath()
    c.restoreGState()

    // feather
    let f = Feather(L: 580, w: 98)
    let origin = CGPoint(x: 318, y: 318), ang = CGFloat.pi / 4
    let vane = place(f.vane, at: origin, angle: ang)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.45))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.addPath(vane); c.clip()
    let fg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1),
        CGColor(red: 0.80, green: 0.86, blue: 0.98, alpha: 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(fg, start: CGPoint(x: 700, y: 760), end: CGPoint(x: 330, y: 330), options: [])
    c.resetClip()
    // spine and a few barb notches cut into the vane
    c.setBlendMode(.clear); c.setLineCap(.round); c.setLineWidth(11)
    c.addPath(place(f.line(0.2, 0.9), at: origin, angle: ang)); c.strokePath()
    c.setLineWidth(7)
    for i in 0..<4 {
        let t = 0.36 + CGFloat(i) * 0.14
        let p = CGMutablePath()
        p.move(to: CGPoint(x: t * f.L, y: 0)); p.addLine(to: CGPoint(x: (t + 0.09) * f.L, y: f.w * (0.80 - CGFloat(i) * 0.14)))
        c.addPath(place(p, at: origin, angle: ang)); c.strokePath()
        let q = CGMutablePath()
        q.move(to: CGPoint(x: t * f.L, y: 0)); q.addLine(to: CGPoint(x: (t + 0.07) * f.L, y: -f.w * (0.62 - CGFloat(i) * 0.12)))
        c.addPath(place(q, at: origin, angle: ang)); c.strokePath()
    }
    c.setBlendMode(.normal)
    // shaft to the nib
    c.setStrokeColor(CGColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)); c.setLineWidth(20)
    c.addPath(place(f.line(-0.12, 0.22), at: origin, angle: ang)); c.strokePath()
    c.endTransparencyLayer()
    c.restoreGState()
    // ink line the nib is writing
    c.setStrokeColor(CGColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 0.95)); c.setLineWidth(22); c.setLineCap(.round)
    c.move(to: CGPoint(x: 238, y: 262)); c.addCurve(to: CGPoint(x: 560, y: 252), control1: CGPoint(x: 330, y: 300), control2: CGPoint(x: 440, y: 205))
    c.strokePath()
}

func renderAppIcon(px: Int) -> CGImage {
    let c = makeContext(px, px)
    c.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawAppIcon(in: c)
    return c.makeImage()!
}

let iconset = NSTemporaryDirectory() + "Quill-\(getpid()).iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(renderAppIcon(px: base), to: "\(iconset)/icon_\(base)x\(base).png")
    writePNG(renderAppIcon(px: base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", root + "/Resources/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
try? fm.removeItem(atPath: iconset)
if task.terminationStatus != 0 { print("iconutil failed"); exit(1) }

// MARK: - Preview sheet

let W = 1400, H = 900
let pc = makeContext(W, H)
pc.setFillColor(CGColor(gray: 0.5, alpha: 1)); pc.fill(CGRect(x: 0, y: 0, width: W, height: H))
pc.draw(renderAppIcon(px: 640), in: CGRect(x: 10, y: 130, width: 640, height: 640))

func label(_ text: String, at p: CGPoint, color: NSColor, size: CGFloat = 16) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: pc, flipped: false)
    (text as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    NSGraphicsContext.restoreGraphicsState()
}
func tinted(_ img: CGImage, in rect: CGRect, color: CGColor) {
    pc.beginTransparencyLayer(auxiliaryInfo: nil)
    pc.draw(img, in: rect)
    pc.setBlendMode(.sourceIn); pc.setFillColor(color); pc.fill(rect)
    pc.endTransparencyLayer()
}
label("Quill", at: CGPoint(x: 30, y: 800), color: .white, size: 28)

let strips: [(String, CGColor, NSColor, CGColor)] = [
    ("light", CGColor(gray: 0.96, alpha: 1), .black, CGColor(gray: 0.1, alpha: 1)),
    ("dark", CGColor(gray: 0.16, alpha: 1), .white, CGColor(gray: 0.95, alpha: 1))]
for (i, st) in strips.enumerated() {
    let y0 = CGFloat(H - 60 - 400 * (i + 1) + 40 * i + 0)
    let rect = CGRect(x: 690, y: y0, width: 690, height: 380)
    pc.setFillColor(st.1); pc.fill(rect)
    label(st.0 + " menu bar", at: CGPoint(x: rect.minX + 16, y: rect.maxY - 30), color: st.2.withAlphaComponent(0.6), size: 14)
    for (j, s) in State.allCases.enumerated() {
        let x = rect.minX + 20 + CGFloat(j) * 132
        tinted(renderMark(s, px: 36), in: CGRect(x: x + 37, y: rect.maxY - 90, width: 36, height: 36), color: st.3)
        tinted(renderMark(s, px: 360), in: CGRect(x: x, y: rect.minY + 50, width: 110, height: 110), color: st.3)
        label(s.rawValue, at: CGPoint(x: x + 20, y: rect.minY + 20), color: st.2.withAlphaComponent(0.7), size: 14)
    }
}
// small row of the 2x marks at 1:1 beside the large app icon
writePNG(pc.makeImage()!, to: root + "/Resources/icon-preview.png")
print("done")
