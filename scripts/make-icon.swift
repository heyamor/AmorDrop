#!/usr/bin/env swift
// Generates an `.iconset` directory of PNGs for the AmorDrop app.
// Pipe into `iconutil -c icns -o AppIcon.icns AppIcon.iconset/` to produce
// the final .icns. Each rendition is drawn fresh at the exact pixel size
// (rather than scaled from a master PNG) so strokes stay crisp at 16px.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    print("usage: make-icon.swift <output-iconset-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// macOS icon size table. Each entry is (filename, pixel size).
let renditions: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// Flat A monogram: the counter is a shelf holding a file. Coordinates are
// normalized to 1000 so every PNG rendition and the PDF use the same paths.
func drawMark(into ctx: CGContext, rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY)
    ctx.scaleBy(x: rect.width / 1000, y: rect.height / 1000)
    let a = CGMutablePath()
    a.move(to: CGPoint(x: 145, y: 160))
    a.addCurve(to: CGPoint(x: 113, y: 223), control1: CGPoint(x: 112, y: 160), control2: CGPoint(x: 97, y: 190))
    a.addLine(to: CGPoint(x: 386, y: 788))
    a.addCurve(to: CGPoint(x: 481, y: 854), control1: CGPoint(x: 405, y: 832), control2: CGPoint(x: 441, y: 854))
    a.addLine(to: CGPoint(x: 519, y: 854))
    a.addCurve(to: CGPoint(x: 614, y: 788), control1: CGPoint(x: 559, y: 854), control2: CGPoint(x: 595, y: 832))
    a.addLine(to: CGPoint(x: 887, y: 223))
    a.addCurve(to: CGPoint(x: 855, y: 160), control1: CGPoint(x: 903, y: 190), control2: CGPoint(x: 888, y: 160))
    a.addLine(to: CGPoint(x: 786, y: 160))
    a.addCurve(to: CGPoint(x: 722, y: 202), control1: CGPoint(x: 756, y: 160), control2: CGPoint(x: 737, y: 174))
    a.addLine(to: CGPoint(x: 696, y: 240))
    a.addCurve(to: CGPoint(x: 644, y: 270), control1: CGPoint(x: 686, y: 260), control2: CGPoint(x: 670, y: 270))
    a.addLine(to: CGPoint(x: 356, y: 270))
    a.addCurve(to: CGPoint(x: 304, y: 240), control1: CGPoint(x: 330, y: 270), control2: CGPoint(x: 314, y: 260))
    a.addLine(to: CGPoint(x: 278, y: 202))
    a.addCurve(to: CGPoint(x: 214, y: 160), control1: CGPoint(x: 263, y: 174), control2: CGPoint(x: 244, y: 160))
    a.closeSubpath()
    // Transparent counter; the bottom edge forms the white shelf.
    a.move(to: CGPoint(x: 285, y: 350))
    a.addCurve(to: CGPoint(x: 287, y: 370), control1: CGPoint(x: 276, y: 350), control2: CGPoint(x: 272, y: 364))
    a.addLine(to: CGPoint(x: 326, y: 370))
    a.addLine(to: CGPoint(x: 437, y: 590))
    a.addCurve(to: CGPoint(x: 563, y: 590), control1: CGPoint(x: 465, y: 652), control2: CGPoint(x: 533, y: 652))
    a.addLine(to: CGPoint(x: 674, y: 370))
    a.addLine(to: CGPoint(x: 713, y: 370))
    a.addCurve(to: CGPoint(x: 715, y: 350), control1: CGPoint(x: 728, y: 364), control2: CGPoint(x: 724, y: 350))
    a.closeSubpath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(a)
    ctx.drawPath(using: .eoFill)
    let file = CGMutablePath()
    file.move(to: CGPoint(x: 439, y: 375))
    file.addLine(to: CGPoint(x: 599, y: 375))
    file.addLine(to: CGPoint(x: 599, y: 447))
    file.addQuadCurve(to: CGPoint(x: 591, y: 455), control: CGPoint(x: 599, y: 455))
    file.addLine(to: CGPoint(x: 569, y: 455))
    file.addQuadCurve(to: CGPoint(x: 549, y: 475), control: CGPoint(x: 549, y: 455))
    file.addLine(to: CGPoint(x: 549, y: 527))
    file.addQuadCurve(to: CGPoint(x: 538, y: 538), control: CGPoint(x: 549, y: 538))
    file.addLine(to: CGPoint(x: 451, y: 538))
    file.addQuadCurve(to: CGPoint(x: 439, y: 526), control: CGPoint(x: 439, y: 538))
    file.closeSubpath()
    ctx.addPath(file)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawIcon(into ctx: CGContext, pixels: Int) {
    let p = CGFloat(pixels)
    let tile = CGRect(x: p * 0.025, y: p * 0.025, width: p * 0.95, height: p * 0.95)
    ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: p * 0.21, cornerHeight: p * 0.21, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(gray: 0.87, alpha: 1))
    ctx.setLineWidth(max(0.5, p * 0.001))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: p * 0.21, cornerHeight: p * 0.21, transform: nil))
    ctx.strokePath()
    drawMark(into: ctx, rect: CGRect(x: p * 0.10, y: p * 0.07, width: p * 0.80, height: p * 0.80))
}

func writePNG(pixels: Int, to url: URL) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write("Failed to make context for \(pixels)\n".data(using: .utf8)!)
        return
    }
    drawIcon(into: ctx, pixels: pixels)
    guard let cgImage = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixels, height: pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

for (name, pixels) in renditions {
    writePNG(pixels: pixels, to: outDir.appendingPathComponent(name))
    print("• wrote \(name) (\(pixels)px)")
}

// A vector template image stays sharp on both Retina and standard displays.
var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdfURL = outDir.appendingPathComponent("MenuBarIcon.pdf")
guard let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else { exit(1) }
pdf.beginPDFPage(nil)
drawMark(into: pdf, rect: mediaBox)
pdf.endPDFPage()
pdf.closePDF()
