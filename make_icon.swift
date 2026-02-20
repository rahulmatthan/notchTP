#!/usr/bin/env swift
// Generates AppIcon.iconset/ at all required macOS sizes, then you run:
//   iconutil -c icns AppIcon.iconset

import AppKit

func drawIcon(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let bg = NSColor(calibratedRed: 0.05, green: 0.055, blue: 0.085, alpha: 1)

    // ── Background ──────────────────────────────────────────────────
    bg.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    // ── Panel ───────────────────────────────────────────────────────
    let pw = s * 0.70,  ph = s * 0.50
    let px = (s - pw) / 2,  py = (s - ph) / 2
    let cr = s * 0.055   // bottom corner radius

    // Fill with a full rounded rect first, then square-off the top corners
    let panelRect = NSRect(x: px, y: py, width: pw, height: ph)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: panelRect, xRadius: cr, yRadius: cr).fill()

    // Square the top-left and top-right corners
    bg.setFill()
    NSBezierPath(rect: NSRect(x: px,            y: py + ph - cr, width: cr, height: cr)).fill()
    NSBezierPath(rect: NSRect(x: px + pw - cr,  y: py + ph - cr, width: cr, height: cr)).fill()

    // Panel border (sides + bottom only, redraw cleanly)
    NSColor(white: 1, alpha: 0.10).setStroke()
    let border = NSBezierPath()
    border.lineWidth = max(0.5, s * 0.003)
    // top edge
    border.move(to: NSPoint(x: px,      y: py + ph))
    border.line(to: NSPoint(x: px + pw, y: py + ph))
    // right side + bottom-right arc (approximated)
    border.line(to: NSPoint(x: px + pw, y: py + cr))
    border.curve(to:          NSPoint(x: px + pw - cr, y: py),
                 controlPoint1: NSPoint(x: px + pw, y: py + cr * 0.45),
                 controlPoint2: NSPoint(x: px + pw - cr * 0.45, y: py))
    // bottom edge + bottom-left arc
    border.line(to: NSPoint(x: px + cr, y: py))
    border.curve(to:          NSPoint(x: px, y: py + cr),
                 controlPoint1: NSPoint(x: px + cr * 0.45, y: py),
                 controlPoint2: NSPoint(x: px, y: py + cr * 0.45))
    // left side
    border.line(to: NSPoint(x: px, y: py + ph))
    border.stroke()

    // ── Top bar (the "notch strip") ──────────────────────────────────
    let tbH   = ph * 0.20
    let tbBotY = py + ph - tbH   // y-coordinate of the separator line

    // Separator
    NSColor(white: 1, alpha: 0.07).setFill()
    NSBezierPath(rect: NSRect(x: px, y: tbBotY, width: pw, height: max(1, s * 0.002))).fill()

    // Notch pill (camera housing representation)
    let nw = pw * 0.38,  nh = tbH * 0.58
    let nx = px + (pw - nw) / 2,  ny = tbBotY + (tbH - nh) / 2
    bg.setFill()
    NSBezierPath(roundedRect: NSRect(x: nx, y: ny, width: nw, height: nh),
                 xRadius: nh / 2, yRadius: nh / 2).fill()

    // ── Text lines ───────────────────────────────────────────────────
    let textTop = tbBotY - s * 0.03
    let textBot = py + s * 0.03
    let availH  = textTop - textBot

    let lh  = max(2, s * 0.022)
    let gap = lh * 0.78
    let widths: [CGFloat] = [0.84, 0.93, 0.75, 0.58]
    let totalH = lh * CGFloat(widths.count) + gap * CGFloat(widths.count - 1)

    // Centre lines in the text area; first line nearest the top bar (high y)
    var ly = textTop - (availH - totalH) / 2 - lh

    for (i, wf) in widths.enumerated() {
        let lw = pw * wf * 0.85
        let lx = px + (pw - lw) / 2
        let alpha: CGFloat = [0.90, 0.70, 0.45, 0.25][i]
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: lx, y: ly, width: lw, height: lh),
                     xRadius: lh / 2, yRadius: lh / 2).fill()
        ly -= (lh + gap)
    }

    img.unlockFocus()
    return img
}

// ── Save all required icon sizes ────────────────────────────────────
let iconsetPath = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath,
                                         withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in specs {
    let img = drawIcon(size: CGFloat(size))
    guard let tiff = img.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff),
          let data = bmp.representation(using: .png, properties: [:]) else {
        print("✗ \(name)"); continue
    }
    try! data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    print("✓ \(name)")
}
print("\nDone. Now run:  iconutil -c icns AppIcon.iconset")
