#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// 明目（Iris）App 图标生成器
//
// 遵循 Apple 图标规范：
//   - 画布 1024×1024，主体内容 824×824 居中（四周留 100px 给系统阴影）
//   - 主体使用连续曲率的超椭圆（squircle，指数 5，等价于圆角半径 185.4）
//   - 全部尺寸同时输出，交给 iconutil 打包成 .icns
//
// 用法：swift scripts/make-icon.swift <输出 iconset 目录>

// MARK: - 工具

/// 超椭圆路径：|x/a|^n + |y/b|^n = 1，n≈5 时非常接近 Apple 的图标形状。
func superellipsePath(in rect: CGRect, exponent: CGFloat = 5, samples: Int = 720) -> CGPath {
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let path = CGMutablePath()

    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = cx + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = cy + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func hex(_ v: Int, _ a: CGFloat = 1) -> CGColor {
    color(CGFloat((v >> 16) & 0xFF) / 255,
          CGFloat((v >> 8) & 0xFF) / 255,
          CGFloat(v & 0xFF) / 255, a)
}

/// 把文字转成路径：这样数字和圆环、圆点可以共用同一套填色逻辑。
func glyphPath(_ string: String, font: NSFont) -> CGPath {
    let attributed = NSAttributedString(string: string, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let path = CGMutablePath()
    guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return path }
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
        CTRunGetPositions(run, CFRangeMake(0, count), &positions)
        for i in 0..<count {
            guard let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
            path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x,
                                                         y: positions[i].y))
        }
    }
    return path
}

// MARK: - 绘制

func drawIcon(size: CGFloat, compact: Bool = false) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("无法创建位图")
    }
    rep.size = NSSize(width: size, height: size)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("无法创建绘图上下文")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let s = size / 1024.0            // 设计稿按 1024 绘制，这里整体缩放
    let content = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = superellipsePath(in: content)

    // ── 1. 底色：靛蓝 → 紫（左上 → 右下）
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [hex(0x7C8CF8), hex(0xA97CF5)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(base,
                           start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY),
                           options: [])
    ctx.restoreGState()

    // ── 2.「20」：0 画成环 + 点，也就是一只眼睛
    //     沿用设计稿坐标（1024），这里整体缩放。
    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)
    drawTwenty(ctx, CGRect(x: 100, y: 100, width: 824, height: 824), compact: compact)
    ctx.restoreGState()

    return rep
}

/// 「20」字标。参数是 1024 画布下的设计稿坐标。
///
/// `compact` 是给 16/32px 用的：笔画加粗、字号加大、整组略微放大，
/// 否则缩到 16px 会糊成一团（Finder 列表视图用的就是这个尺寸）。
func drawTwenty(_ ctx: CGContext, _ content: CGRect, compact: Bool = false) {
    let ringRadius: CGFloat = 165
    let ringWidth: CGFloat = compact ? 92 : 72
    let dotRadius: CGFloat = compact ? 54 : 48
    let gap: CGFloat = 58
    let groupScale: CGFloat = compact ? 1.16 : 1.0

    let font = NSFont.systemFont(ofSize: compact ? 470 : 430,
                                 weight: compact ? .bold : .semibold)
    let two = glyphPath("2", font: font)
    let box = two.boundingBoxOfPath

    let outer = ringRadius + ringWidth / 2
    let ringCX = content.midX + outer / 2 + 10
    let ringCY = content.midY

    // 数字右缘贴着圆环外缘，留一个 gap
    let twoX = ringCX - outer - gap - box.width - box.minX
    let twoY = content.midY - box.height / 2 - box.minY

    // 按整组包围盒做光学居中
    let dx = content.midX - ((twoX + box.minX) + (ringCX + outer)) / 2

    let white = color(1, 1, 1, 0.97)
    ctx.setFillColor(white)

    ctx.saveGState()
    if groupScale != 1 {
        ctx.translateBy(x: content.midX, y: content.midY)
        ctx.scaleBy(x: groupScale, y: groupScale)
        ctx.translateBy(x: -content.midX, y: -content.midY)
    }
    ctx.translateBy(x: dx, y: 0)
    let placed = CGMutablePath()
    placed.addPath(two, transform: CGAffineTransform(translationX: twoX, y: twoY))
    ctx.addPath(placed)
    ctx.fillPath()

    let ringRect = CGRect(x: ringCX - ringRadius, y: ringCY - ringRadius,
                          width: ringRadius * 2, height: ringRadius * 2)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(ringWidth)
    ctx.strokeEllipse(in: ringRect)

    ctx.fillEllipse(in: CGRect(x: ringCX - dotRadius, y: ringCY - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2))
    ctx.restoreGState()
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败：\(url.lastPathComponent)")
    }
    try? data.write(to: url)
}

// MARK: - 主流程

let arguments = CommandLine.arguments
let outputDir = URL(fileURLWithPath: arguments.count > 1
                    ? arguments[1]
                    : FileManager.default.currentDirectoryPath + "/AppIcon.iconset")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// iconutil 要求的尺寸清单（含 @2x）
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

// 高分辨率版本只画一次，小尺寸直接从它缩下来（保持视觉一致）
let master = drawIcon(size: 1024)

for variant in variants {
    let url = outputDir.appendingPathComponent("\(variant.name).png")
    if variant.pixels == 1024 {
        writePNG(master, to: url)
    } else if variant.pixels <= 32 {
        // 16/32px 直接按紧凑版重画，而不是把 1024 缩下来
        writePNG(drawIcon(size: variant.pixels, compact: true), to: url)
    } else {
        let target = Int(variant.pixels)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: target, pixelsHigh: target,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        rep.size = NSSize(width: variant.pixels, height: variant.pixels)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { continue }
        ctx.interpolationQuality = .high
        if let cgImage = master.cgImage {
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))
        }
        writePNG(rep, to: url)
    }
    print("  · \(variant.name).png")
}

// 顺便输出一张 512 的预览，方便肉眼检查
writePNG(master, to: outputDir.appendingPathComponent("preview-1024.png"))
print("图标已生成：\(outputDir.path)")
