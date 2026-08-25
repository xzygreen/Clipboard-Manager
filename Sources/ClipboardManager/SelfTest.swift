import Foundation
import AppKit

/// 不依赖 GUI 的存储逻辑自测。通过 `--selftest` 触发,完成后按是否全部通过 exit(0/1)。
enum SelfTest {

    static func run() -> Never {
        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            print(cond ? "  ✅ \(msg)" : "  ❌ \(msg)")
            if !cond { failures += 1 }
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cbm-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        print("== HistoryStore 自测 ==")

        // --- 文本:顺序 / 去重移顶 / 容量 / 置顶保护 ---
        let textDir = tmp.appendingPathComponent("text")
        let store = HistoryStore(maxItems: 3, baseDirectory: textDir)

        store.add(.text("a"), sourceApp: nil)
        store.add(.text("b"), sourceApp: nil)
        store.add(.text("c"), sourceApp: nil)
        check(store.items.map { $0.text } == ["c", "b", "a"], "插入顺序:最新在前")

        store.add(.text("a"), sourceApp: nil)
        check(store.items.map { $0.text } == ["a", "c", "b"], "重复内容移到顶部、不新增")

        store.add(.text("d"), sourceApp: nil)
        check(store.items.map { $0.text } == ["d", "a", "c"], "超容量淘汰最旧的非置顶项")

        store.add(.text("d"), sourceApp: nil)
        check(store.items.count == 3 && store.items.first?.text == "d", "与最新相同则忽略")

        if let c = store.items.first(where: { $0.text == "c" }) { store.togglePin(c) }
        store.add(.text("e"), sourceApp: nil)
        store.add(.text("f"), sourceApp: nil)
        check(store.items.contains { $0.text == "c" && $0.pinned }, "置顶项不被容量淘汰")

        // --- 图片:按内容哈希去重 + 落盘 + 持久化往返 ---
        let mediaDir = tmp.appendingPathComponent("media")
        let store2 = HistoryStore(maxItems: 50, baseDirectory: mediaDir)
        store2.add(.text("hello"), sourceApp: "Test")

        let png = makeRedPNG()
        store2.add(.image(png, pixelSize: "128×128"), sourceApp: nil)
        store2.add(.image(png, pixelSize: "128×128"), sourceApp: nil)   // 同图
        let imgItems = store2.items.filter { $0.kind == .image }
        check(imgItems.count == 1, "相同图片按内容哈希去重(只留一条)")
        if let item = imgItems.first, let url = store2.imageURL(for: item) {
            check(FileManager.default.fileExists(atPath: url.path), "图片 PNG 已落盘")
        } else {
            check(false, "图片条目缺少落盘文件")
        }
        // 缩略图:把 128px 源图缩到 ≤64px(列表滚动性能关键路径)
        if let item = imgItems.first, let thumb = store2.thumbnail(for: item, maxPixel: 64) {
            check(max(thumb.size.width, thumb.size.height) <= 64, "缩略图缩放到 ≤64px(性能优化)")
        } else {
            check(false, "缩略图生成失败")
        }

        store2.saveNow()
        let reopened = HistoryStore(maxItems: 50, baseDirectory: mediaDir)
        check(reopened.items.map { $0.previewText } == store2.items.map { $0.previewText },
              "重新打开后历史一致(持久化往返)")
        check(reopened.items.contains { $0.kind == .image }, "图片条目持久化保留")

        // --- 清空 ---
        store2.clearAll()
        check(store2.items.isEmpty, "清空后历史为空")

        print(failures == 0 ? "\n全部通过 ✅" : "\n有 \(failures) 项失败 ❌")
        exit(failures == 0 ? 0 : 1)
    }

    /// 构造一张 128×128 纯红 PNG(不走 lockFocus,headless 安全)。
    private static func makeRedPNG() -> Data {
        let side = 128
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: side, pixelsHigh: side,
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        for x in 0..<side {
            for y in 0..<side {
                rep.setColor(red, atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
