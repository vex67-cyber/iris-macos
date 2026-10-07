#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// 生成 DMG 安装窗口的背景图（1x = 660×420，同时输出 @2x）
// 风格：极浅的渐变 + 一枚从 App 指向「应用程序」的箭头 + 顶部品牌署标。

func drawBackground(size: CGSize, scale: CGFloat) -> NSBitmapImageRep {
    let pixelsWide = Int(size.width * scale)
    let pixelsHigh = Int(size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("无法创建位图")
    }
    rep.size = size

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("无法创建上下文")
    }
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let rect = CGRect(origin: .zero, size: size)

    // 1. 底色：极浅的暖白 → 淡青
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1),
                                 CGColor(red: 0.94, green: 0.98, blue: 0.98, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size.height),
                           end: CGPoint(x: size.width, y: 0), options: [])

    // 2. 左右各一团品牌色柔光（不打扰图标阅读，只是氛围）
    let glowTeal = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.20, green: 0.78, blue: 0.71, alpha: 0.22),
                                       CGColor(red: 0.20, green: 0.78, blue: 0.71, alpha: 0)] as CFArray,
                              locations: [0, 1])!
    ctx.drawRadialGradient(glowTeal,
                           startCenter: CGPoint(x: 150, y: 150), startRadius: 0,
                           endCenter: CGPoint(x: 150, y: 150), endRadius: 240, options: [])

    let glowIndigo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [CGColor(red: 0.49, green: 0.55, blue: 0.97, alpha: 0.20),
                                         CGColor(red: 0.49, green: 0.55, blue: 0.97, alpha: 0)] as CFArray,
                                locations: [0, 1])!
    ctx.drawRadialGradient(glowIndigo,
                           startCenter: CGPoint(x: 510, y: 140), startRadius: 0,
                           endCenter: CGPoint(x: 510, y: 140), endRadius: 240, options: [])

    // 3. 中间箭头（App → 应用程序）
    // 与图标位置对齐：Finder 里图标中心在距顶部 200pt 处，而这里是底部原点坐标
    let arrowY: CGFloat = size.height - 200
    let arrowStart: CGFloat = 258
    let arrowEnd: CGFloat = 402

    let arrowColor = CGColor(red: 0.42, green: 0.46, blue: 0.55, alpha: 0.62)

    // 虚线尾巴：暗示"拖过去"
    ctx.setStrokeColor(arrowColor)
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [7, 7])
    ctx.move(to: CGPoint(x: arrowStart, y: arrowY))
    ctx.addLine(to: CGPoint(x: arrowEnd - 14, y: arrowY))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    // 实心箭头
    ctx.setFillColor(arrowColor)
    ctx.move(to: CGPoint(x: arrowEnd, y: arrowY))
    ctx.addLine(to: CGPoint(x: arrowEnd - 16, y: arrowY + 9))
    ctx.addLine(to: CGPoint(x: arrowEnd - 16, y: arrowY - 9))
    ctx.closePath()
    ctx.fillPath()

    // 4. 文案
    func draw(_ text: String, at point: CGPoint, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(white: 0.25, alpha: alpha),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: point.x - bounds.width / 2, y: point.y)
        CTLineDraw(line, ctx)
    }

    draw("把「明目」拖进「应用程序」", at: CGPoint(x: size.width / 2, y: 104), size: 13, weight: .medium, alpha: 0.66)
    draw("拖入后即可从启动台或「应用程序」打开", at: CGPoint(x: size.width / 2, y: 82), size: 11, weight: .regular, alpha: 0.42)

    return rep
}

let args = CommandLine.arguments
let outputDir = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let size = CGSize(width: 660, height: 420)
for (name, scale) in [("background.png", CGFloat(1)), ("background@2x.png", CGFloat(2))] {
    let rep = drawBackground(size: size, scale: scale)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: outputDir.appendingPathComponent(name))
    print("  · \(name)")
}
