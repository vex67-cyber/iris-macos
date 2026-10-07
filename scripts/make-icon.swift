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

// MARK: - 绘制

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
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

    // ── 1. 底部渐变（明目青 → 天蓝 → 靛蓝）
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.18, 0.86, 0.74),
                                   color(0.17, 0.62, 0.98),
                                   color(0.40, 0.42, 0.96)] as CFArray,
                          locations: [0.0, 0.52, 1.0])!
    ctx.drawLinearGradient(base,
                           start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY),
                           options: [])

    // ── 2. 顶部柔光（让整块"玻璃"有厚度）
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(1, 1, 1, 0.30), color(1, 1, 1, 0)] as CFArray,
                               locations: [0, 1])!
    ctx.drawRadialGradient(highlight,
                           startCenter: CGPoint(x: content.midX, y: content.maxY),
                           startRadius: 0,
                           endCenter: CGPoint(x: content.midX, y: content.maxY),
                           endRadius: 640 * s,
                           options: [])

    // ── 3. 底部内阴影（体积感）
    let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0, 0, 0, 0), color(0.05, 0.10, 0.35, 0.22)] as CFArray,
                              locations: [0, 1])!
    ctx.drawRadialGradient(vignette,
                           startCenter: CGPoint(x: content.midX, y: content.midY),
                           startRadius: 120 * s,
                           endCenter: CGPoint(x: content.midX, y: content.midY),
                           endRadius: 700 * s,
                           options: [])
    ctx.restoreGState()

    // ── 4. 眼睛
    let cx = content.midX
    let cy = content.midY
    let halfW = 262 * s
    let bulge = 208 * s

    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: cx - halfW, y: cy))
    eye.addCurve(to: CGPoint(x: cx + halfW, y: cy),
                 control1: CGPoint(x: cx - 96 * s, y: cy + bulge),
                 control2: CGPoint(x: cx + 96 * s, y: cy + bulge))
    eye.addCurve(to: CGPoint(x: cx - halfW, y: cy),
                 control1: CGPoint(x: cx + 96 * s, y: cy - bulge),
                 control2: CGPoint(x: cx - 96 * s, y: cy - bulge))
    eye.closeSubpath()

    ctx.setLineWidth(30 * s)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(1, 1, 1, 0.96))
    ctx.addPath(eye)
    ctx.strokePath()

    // 虹膜：一圈淡淡的白边 + 深色渐变，让眼睛有"神"
    let irisRadius = 112 * s
    let irisRect = CGRect(x: cx - irisRadius, y: cy - irisRadius,
                          width: irisRadius * 2, height: irisRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: irisRect)
    ctx.clip()
    let iris = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.06, 0.16, 0.28),
                                   color(0.10, 0.26, 0.55),
                                   color(0.24, 0.42, 0.85)] as CFArray,
                          locations: [0, 0.6, 1])!
    ctx.drawRadialGradient(iris,
                           startCenter: CGPoint(x: cx - irisRadius * 0.3, y: cy + irisRadius * 0.35),
                           startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy),
                           endRadius: irisRadius * 1.25,
                           options: [])
    ctx.restoreGState()

    // 高光点
    ctx.setFillColor(color(1, 1, 1, 0.92))
    ctx.fillEllipse(in: CGRect(x: cx - 62 * s, y: cy + 20 * s, width: 58 * s, height: 58 * s))

    return rep
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
