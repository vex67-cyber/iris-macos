#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// 明目 App 图标候选方案（用于挑选，不是最终产物）
//
// 这些是当时画出来对比的备选，正式图标在 scripts/make-icon.swift：
// 最终选的是「二十」那个方向（0 画成环 + 点 = 一只眼睛），配色靛蓝 → 紫。
// 留着这份是为了以后想再改图标时，不用从零开始画。
//
// 用法：swift scripts/icon-candidates.swift <输出目录>

func superellipsePath(in rect: CGRect, exponent: CGFloat = 5, samples: Int = 720) -> CGPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = CGMutablePath()
    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / exponent), c)
        let y = cy + b * copysign(pow(abs(s), 2 / exponent), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

/// 画底色（品牌渐变 + 顶部柔光 + 底部内阴影）
func drawBase(_ ctx: CGContext, content: CGRect) {
    ctx.saveGState()
    ctx.addPath(superellipsePath(in: content))
    ctx.clip()

    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.18, 0.86, 0.74), color(0.17, 0.62, 0.98), color(0.40, 0.42, 0.96)] as CFArray,
                          locations: [0, 0.52, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY), options: [])

    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(1, 1, 1, 0.30), color(1, 1, 1, 0)] as CFArray,
                               locations: [0, 1])!
    ctx.drawRadialGradient(highlight, startCenter: CGPoint(x: content.midX, y: content.maxY),
                           startRadius: 0, endCenter: CGPoint(x: content.midX, y: content.maxY),
                           endRadius: 640, options: [])
    ctx.restoreGState()
}

// MARK: - 方案 A：闭眼（放松）

func drawClosedEye(_ ctx: CGContext, content: CGRect) {
    let cx = content.midX, cy = content.midY
    let halfW: CGFloat = 250

    // 闭着的眼睑：一条向下凸的弧
    let lidDepth: CGFloat = 120
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: cx - halfW, y: cy + 56))
    lid.addCurve(to: CGPoint(x: cx + halfW, y: cy + 56),
                 control1: CGPoint(x: cx - 120, y: cy + 56 - lidDepth),
                 control2: CGPoint(x: cx + 120, y: cy + 56 - lidDepth))

    ctx.setStrokeColor(color(1, 1, 1, 0.97))
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.addPath(lid)
    ctx.strokePath()

    // 睫毛：从眼睑下缘垂下来（外侧两根略外撇），别戳进眼睛里
    ctx.setLineWidth(22)
    for (dx, len, tilt) in [(-148.0, 62.0, -22.0), (-42.0, 74.0, -6.0),
                            (62.0, 70.0, 8.0), (152.0, 56.0, 24.0)] {
        // 沿弧的近似高度：抛物线拟合
        let t = dx / halfW
        let arcY = cy + 56 - lidDepth * (1 - t * t) * 0.75
        let start = CGPoint(x: cx + dx, y: arcY - 26)
        let end = CGPoint(x: cx + dx + sin(tilt * .pi / 180) * len,
                          y: arcY - 26 - cos(tilt * .pi / 180) * len)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
    }
}

// MARK: - 方案 B：几何眼睛（保留眼型，虹膜抽象化）

func drawGeometricEye(_ ctx: CGContext, content: CGRect) {
    let cx = content.midX, cy = content.midY
    let halfW: CGFloat = 262, bulge: CGFloat = 208

    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: cx - halfW, y: cy))
    eye.addCurve(to: CGPoint(x: cx + halfW, y: cy),
                 control1: CGPoint(x: cx - 96, y: cy + bulge),
                 control2: CGPoint(x: cx + 96, y: cy + bulge))
    eye.addCurve(to: CGPoint(x: cx - halfW, y: cy),
                 control1: CGPoint(x: cx + 96, y: cy - bulge),
                 control2: CGPoint(x: cx - 96, y: cy - bulge))
    eye.closeSubpath()

    ctx.setStrokeColor(color(1, 1, 1, 0.96))
    ctx.setLineWidth(30)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(eye)
    ctx.strokePath()

    // 虹膜：一个干净的实心圆，没有任何写实细节
    let r: CGFloat = 112
    ctx.setFillColor(color(1, 1, 1, 0.96))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

// MARK: - 方案 C：抽象虹膜（同心圆）

func drawIrisRings(_ ctx: CGContext, content: CGRect) {
    let cx = content.midX, cy = content.midY

    let rings: [(CGFloat, CGFloat, CGFloat)] = [
        (250, 30, 0.42),   // 半径, 线宽, 不透明度
        (172, 26, 0.70),
        (98, 22, 1.0),
    ]
    for (radius, width, alpha) in rings {
        ctx.setStrokeColor(color(1, 1, 1, alpha))
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                     width: radius * 2, height: radius * 2))
    }
    // 中心实心点
    let dot: CGFloat = 34
    ctx.setFillColor(color(1, 1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: cx - dot, y: cy - dot, width: dot * 2, height: dot * 2))
}


// MARK: - 方案 D：远眺（地平线 + 日出）

func drawHorizon(_ ctx: CGContext, content: CGRect) {
    ctx.saveGState()
    ctx.addPath(superellipsePath(in: content))
    ctx.clip()

    // 天空：深靛 → 青 → 地平线附近的暖光
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [color(0.05, 0.12, 0.24), color(0.06, 0.28, 0.36),
                                  color(0.13, 0.52, 0.55), color(0.62, 0.78, 0.62)] as CFArray,
                         locations: [0, 0.45, 0.72, 1.0])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: content.midX, y: content.maxY),
                           end: CGPoint(x: content.midX, y: content.minY), options: [])

    // 太阳：地平线上方的暖色圆盘 + 光晕
    let horizonY = content.minY + 300
    let sunCenter = CGPoint(x: content.midX, y: horizonY + 96)
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(1.0, 0.92, 0.72, 0.55), color(1.0, 0.85, 0.6, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: sunCenter, startRadius: 0,
                           endCenter: sunCenter, endRadius: 360, options: [])

    ctx.setFillColor(color(1.0, 0.96, 0.86, 0.98))
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - 112, y: sunCenter.y - 112, width: 224, height: 224))

    // 地面：两层半透明的远山剪影
    func ridge(baseY: CGFloat, peaks: [(CGFloat, CGFloat)], alpha: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: content.minX - 40, y: baseY))
        for (x, h) in peaks {
            path.addLine(to: CGPoint(x: x - 150, y: baseY))
            path.addLine(to: CGPoint(x: x, y: baseY + h))
            path.addLine(to: CGPoint(x: x + 170, y: baseY))
        }
        path.addLine(to: CGPoint(x: content.maxX + 40, y: baseY))
        path.addLine(to: CGPoint(x: content.maxX + 40, y: content.minY - 40))
        path.addLine(to: CGPoint(x: content.minX - 40, y: content.minY - 40))
        path.closeSubpath()
        ctx.setFillColor(color(0.04, 0.12, 0.20, alpha))
        ctx.addPath(path)
        ctx.fillPath()
    }
    ridge(baseY: horizonY, peaks: [(content.midX - 250, 150), (content.midX + 210, 110)], alpha: 0.45)
    ridge(baseY: horizonY - 60, peaks: [(content.midX - 90, 210), (content.midX + 300, 130)], alpha: 0.85)

    ctx.restoreGState()
}

// MARK: - 方案 E：极简环（深色底，对比强烈）

func drawMinimalRing(_ ctx: CGContext, content: CGRect) {
    ctx.saveGState()
    ctx.addPath(superellipsePath(in: content))
    ctx.clip()

    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0.07, 0.16, 0.27), color(0.06, 0.30, 0.36), color(0.10, 0.44, 0.48)] as CFArray,
                        locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY), options: [])

    let cx = content.midX, cy = content.midY

    // 环的柔光
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.35, 0.95, 0.85, 0.45), color(0.35, 0.95, 0.85, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: cx, y: cy), startRadius: 120,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: 420, options: [])

    // 主环
    ctx.setStrokeColor(color(0.96, 1.0, 0.99, 1))
    ctx.setLineWidth(46)
    ctx.strokeEllipse(in: CGRect(x: cx - 208, y: cy - 208, width: 416, height: 416))

    // 中心圆点
    ctx.setFillColor(color(0.45, 0.98, 0.88, 1))
    ctx.fillEllipse(in: CGRect(x: cx - 62, y: cy - 62, width: 124, height: 124))

    ctx.restoreGState()
}

// MARK: - 方案 F：20（把 0 画成眼睛）

func drawTwenty(_ ctx: CGContext, content: CGRect) {
    let cx = content.midX, cy = content.midY

    // "2" 用系统圆体渲染
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 430, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    let two = NSAttributedString(string: "2", attributes: attributes)
    let line = CTLineCreateWithAttributedString(two)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    // "0" 画成一个环 + 中心点（也就是眼睛）
    let ringRadius: CGFloat = 168
    let zeroCenter = CGPoint(x: cx + 190, y: cy)
    let twoWidth = bounds.width
    ctx.textPosition = CGPoint(x: zeroCenter.x - 130 - ringRadius * 0.55 - twoWidth, y: cy - bounds.height / 2 - bounds.origin.y)
    CTLineDraw(line, ctx)

    ctx.setStrokeColor(color(1, 1, 1, 0.97))
    ctx.setLineWidth(70)
    ctx.strokeEllipse(in: CGRect(x: zeroCenter.x - ringRadius, y: zeroCenter.y - ringRadius,
                                 width: ringRadius * 2, height: ringRadius * 2))

    ctx.setFillColor(color(1, 1, 1, 0.97))
    let dot: CGFloat = 46
    ctx.fillEllipse(in: CGRect(x: zeroCenter.x - dot, y: zeroCenter.y - dot, width: dot * 2, height: dot * 2))
}


// MARK: - 方案 G：扁平工具风（像 macOS 自带工具类 App）

func drawFlatUtility(_ ctx: CGContext, content: CGRect) {
    // 纯色底，没有渐变——Apple 的工具类图标就是这个路数
    ctx.setFillColor(color(0.06, 0.42, 0.47))
    ctx.addPath(superellipsePath(in: content))
    ctx.fillPath()

    let cx = content.midX
    let baseY = content.midY - 60

    // 地平线
    ctx.setStrokeColor(color(1, 1, 1, 0.95))
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx - 250, y: baseY))
    ctx.addLine(to: CGPoint(x: cx + 250, y: baseY))
    ctx.strokePath()

    // 地平线上方的半圆（日出/远眺）
    let r: CGFloat = 132
    let arc = CGMutablePath()
    arc.addArc(center: CGPoint(x: cx, y: baseY + 34), radius: r,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.setStrokeColor(color(1, 1, 1, 0.95))
    ctx.setLineWidth(26)
    ctx.addPath(arc)
    ctx.strokePath()
}

// MARK: - 方案 H：暗色玻璃透镜

func drawGlassLens(_ ctx: CGContext, content: CGRect) {
    ctx.saveGState()
    ctx.addPath(superellipsePath(in: content))
    ctx.clip()

    // 近黑的深蓝底 + 中心微光
    ctx.setFillColor(color(0.03, 0.06, 0.11))
    ctx.fill(content)
    let ambience = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0.20, 0.55, 0.62, 0.55), color(0.10, 0.30, 0.40, 0)] as CFArray,
                              locations: [0, 1])!
    ctx.drawRadialGradient(ambience, startCenter: CGPoint(x: content.midX, y: content.midY + 40),
                           startRadius: 40, endCenter: CGPoint(x: content.midX, y: content.midY),
                           endRadius: 470, options: [])

    let cx = content.midX, cy = content.midY
    let r: CGFloat = 250

    // 透镜：半透明玻璃圆
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    ctx.clip()
    let glass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(1, 1, 1, 0.28), color(0.6, 0.9, 0.95, 0.12), color(1, 1, 1, 0.04)] as CFArray,
                           locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: cx - r, y: cy + r),
                           end: CGPoint(x: cx + r, y: cy - r), options: [])
    ctx.restoreGState()

    // 玻璃边缘的高光弧
    ctx.setStrokeColor(color(1, 1, 1, 0.85))
    ctx.setLineWidth(14)
    let rim = CGMutablePath()
    rim.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
    ctx.addPath(rim)
    ctx.strokePath()

    // 外圈细环
    ctx.setStrokeColor(color(1, 1, 1, 0.22))
    ctx.setLineWidth(6)
    ctx.strokeEllipse(in: CGRect(x: cx - r - 40, y: cy - r - 40, width: (r + 40) * 2, height: (r + 40) * 2))

    // 中心的瞳孔点（发光）
    let dotGlow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [color(0.5, 1.0, 0.92, 0.9), color(0.5, 1.0, 0.92, 0)] as CFArray,
                             locations: [0, 1])!
    ctx.drawRadialGradient(dotGlow, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: 170, options: [])
    ctx.setFillColor(color(0.75, 1.0, 0.97, 1))
    ctx.fillEllipse(in: CGRect(x: cx - 52, y: cy - 52, width: 104, height: 104))

    ctx.restoreGState()
}

// MARK: - 方案 I：浅色温和（闭眼 + 睫毛，深色字形）

func drawSoftClosedEye(_ ctx: CGContext, content: CGRect) {
    ctx.saveGState()
    ctx.addPath(superellipsePath(in: content))
    ctx.clip()

    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0.85, 0.97, 0.94), color(0.72, 0.90, 0.98)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY), options: [])
    ctx.restoreGState()

    let cx = content.midX
    let cy = content.midY - 30
    let halfW: CGFloat = 255
    let depth: CGFloat = 130
    let ink = color(0.05, 0.38, 0.42, 1)   // 深青，浅底上很清楚

    // 眼睑：向下的弧
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: cx - halfW, y: cy + 40))
    lid.addCurve(to: CGPoint(x: cx + halfW, y: cy + 40),
                 control1: CGPoint(x: cx - 120, y: cy + 40 - depth),
                 control2: CGPoint(x: cx + 120, y: cy + 40 - depth))
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    ctx.addPath(lid)
    ctx.strokePath()

    // 睫毛：从弧下方垂下来
    ctx.setLineWidth(20)
    for (dx, len, tilt) in [(-140.0, 58.0, -20.0), (-40.0, 70.0, -5.0),
                            (60.0, 66.0, 7.0), (150.0, 52.0, 22.0)] {
        let t = dx / halfW
        let arcY = cy + 40 - depth * (1 - t * t) * 0.72
        ctx.move(to: CGPoint(x: cx + dx, y: arcY - 22))
        ctx.addLine(to: CGPoint(x: cx + dx + sin(tilt * .pi / 180) * len,
                                y: arcY - 22 - cos(tilt * .pi / 180) * len))
        ctx.strokePath()
    }
}

// MARK: - 渲染

func render(name: String, draw: (CGContext, CGRect) -> Void, into dir: URL) {
    let size: CGFloat = 1024
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let content = CGRect(x: 100, y: 100, width: 824, height: 824)
    drawBase(ctx, content: content)
    draw(ctx, content)

    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: dir.appendingPathComponent("\(name)-1024.png"))

    // 缩一份 128 的，方便看小尺寸下的辨识度
    if let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
       let sctx = NSGraphicsContext(bitmapImageRep: small)?.cgContext,
       let cg = rep.cgImage {
        sctx.interpolationQuality = .high
        sctx.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        if let d = small.representation(using: .png, properties: [:]) {
            try? d.write(to: dir.appendingPathComponent("\(name)-128.png"))
        }
    }
    print("  · \(name)")
}

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath + "/icon-candidates")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

render(name: "D-远眺日出", draw: drawHorizon, into: out)
render(name: "E-极简环", draw: drawMinimalRing, into: out)
render(name: "F-二十", draw: drawTwenty, into: out)
render(name: "G-扁平工具", draw: drawFlatUtility, into: out)
render(name: "H-玻璃透镜", draw: drawGlassLens, into: out)
render(name: "I-浅色闭眼", draw: drawSoftClosedEye, into: out)
print("候选图标已生成：\(out.path)")
