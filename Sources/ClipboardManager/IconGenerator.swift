import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 用 CoreGraphics 程序化绘制 App 图标(渐变圆角底板 + 白色剪贴板 + 顶部夹子 + 内容横线)。
///
/// 纯 CG 绘制,不依赖 NSApplication / lockFocus,在 `--makeicon` 模式(应用启动前)安全运行。
/// 通过 `iconutil` 把生成的 `.iconset` 转成 `AppIcon.icns`。
enum IconGenerator {

    /// 把全套尺寸写入一个 `.iconset` 目录。
    static func writeIconset(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // iconutil 需要的命名与像素尺寸
        let specs: [(name: String, px: Int)] = [
            ("icon_16x16", 16),    ("icon_16x16@2x", 32),
            ("icon_32x32", 32),    ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for spec in specs {
            guard let data = pngData(size: spec.px) else { continue }
            try? data.write(to: url.appendingPathComponent("\(spec.name).png"))
        }
        print("iconset 已写入: \(url.path)")
    }

    // MARK: 绘制

    private static func pngData(size: Int) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(in: ctx, size: CGFloat(size), cs: cs)
        guard let image = ctx.makeImage() else { return nil }
        return encodePNG(image)
    }

    private static func draw(in ctx: CGContext, size s: CGFloat, cs: CGColorSpace) {
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: cs, components: [r, g, b, a])!
        }

        // 背景:圆角矩形 + 蓝→紫 渐变
        let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
        let bgRadius = s * 0.2237
        ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil))
        ctx.clip()
        let grad = CGGradient(colorsSpace: cs,
                              colors: [color(0.40, 0.49, 0.99), color(0.55, 0.36, 0.96)] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])

        // 白色底板
        let boardW = s * 0.52, boardH = s * 0.60
        let boardX = (s - boardW) / 2
        let boardY = (s - boardH) / 2 - s * 0.015
        let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
        // 轻微阴影,提升立体感
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.03,
                      color: color(0, 0, 0, 0.18))
        ctx.setFillColor(color(1, 1, 1))
        ctx.addPath(CGPath(roundedRect: boardRect, cornerWidth: s * 0.055, cornerHeight: s * 0.055, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        // 顶部夹子
        let clipW = s * 0.22, clipH = s * 0.105
        let clipX = (s - clipW) / 2
        let clipY = boardY + boardH - clipH * 0.5
        ctx.setFillColor(color(0.29, 0.33, 0.43))
        ctx.addPath(CGPath(roundedRect: CGRect(x: clipX, y: clipY, width: clipW, height: clipH),
                           cornerWidth: clipH * 0.4, cornerHeight: clipH * 0.4, transform: nil))
        ctx.fillPath()

        // 内容横线(浅灰),提示"历史记录";最后一条短一些
        ctx.setFillColor(color(0.80, 0.82, 0.88))
        let lineX = boardX + boardW * 0.16
        let lineW = boardW * 0.68
        let lineH = s * 0.034
        let topLineY = clipY - s * 0.10
        let gap = s * 0.095
        for i in 0..<3 {
            let y = topLineY - CGFloat(i) * gap
            let w = (i == 2) ? lineW * 0.6 : lineW
            ctx.addPath(CGPath(roundedRect: CGRect(x: lineX, y: y, width: w, height: lineH),
                               cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
            ctx.fillPath()
        }
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
