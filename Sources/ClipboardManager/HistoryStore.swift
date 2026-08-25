import Foundation
import AppKit
import Combine
import ImageIO

/// 监听器捕获到的原始内容,交给 `HistoryStore` 决定去重/落盘。
enum CapturedContent {
    case text(String)
    case image(Data, pixelSize: String?)   // PNG 数据
    case files([String])
}

/// 剪贴板历史的内存模型 + 磁盘持久化。
///
/// - 内存中维护一个按时间倒序的数组(最新在前)。
/// - 置顶项在视图里单独成段;容量淘汰只针对非置顶项。
/// - 索引存 `~/Library/Application Support/ClipboardManager/history.json`,
///   图片 PNG 存同目录下的 `images/` 子目录。
final class HistoryStore: ObservableObject {

    @Published private(set) var items: [ClipboardItem] = []

    /// 非置顶项的最大保留条数。
    let maxItems: Int

    /// 写回剪贴板后回调(用于让监听器忽略这次由我们自己造成的变化)。
    var pasteboardWriteHook: (() -> Void)?

    // 存储路径
    private let storeDir: URL
    private let indexURL: URL
    private let imagesDir: URL

    // 图片缓存:imageCache 存原图(写回剪贴板用),thumbCache 存小缩略图(列表展示用)
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbCache = NSCache<NSString, NSImage>()

    // 防抖写盘
    private var saveWorkItem: DispatchWorkItem?

    init(maxItems: Int = 200, baseDirectory: URL? = nil) {
        self.maxItems = maxItems

        let base = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.storeDir = base.appendingPathComponent("ClipboardManager", isDirectory: true)
        self.indexURL = storeDir.appendingPathComponent("history.json")
        self.imagesDir = storeDir.appendingPathComponent("images", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 读取磁盘上的图片(供视图展示)

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let url = imageURL(for: item), let img = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(img, forKey: name as NSString)
        return img
    }

    /// 列表展示用的小缩略图:用 ImageIO 直接解码到目标尺寸并缓存。
    ///
    /// 关键性能点 —— 之前列表直接渲染原图(可能是 2880×1800 的截图),每帧都要把整张大图
    /// 缩放到 36pt,滚动时极卡。这里一次性生成 ~96px 的小图缓存,渲染开销可忽略。
    func thumbnail(for item: ClipboardItem, maxPixel: Int = 96) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        if let cached = thumbCache.object(forKey: name as NSString) { return cached }
        guard let url = imageURL(for: item),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache.setObject(img, forKey: name as NSString)
        return img
    }

    // MARK: - 新增(来自监听器)

    /// 接收一次捕获到的内容。负责去重、移到顶部、图片落盘、容量淘汰。
    func add(_ content: CapturedContent, sourceApp: String?) {
        let (key, hash) = Self.dedupKey(for: content)

        // 与最新一条相同 → 忽略,避免抖动
        if let first = items.first, first.dedupKey == key {
            return
        }

        // 命中较旧的一条 → 移到顶部,保留其置顶状态
        var inheritPinned = false
        if let idx = items.firstIndex(where: { $0.dedupKey == key }) {
            inheritPinned = items[idx].pinned
            removeItem(at: idx)
        }

        // 构造新条目
        var newItem: ClipboardItem
        switch content {
        case .text(let s):
            newItem = ClipboardItem(kind: .text, sourceApp: sourceApp, text: s)
        case .image(let data, let pixelSize):
            let item = ClipboardItem(kind: .image, sourceApp: sourceApp,
                                     imageFileName: nil, imageHash: hash, pixelSize: pixelSize)
            let fileName = "\(item.id.uuidString).png"
            let url = imagesDir.appendingPathComponent(fileName)
            do {
                try data.write(to: url, options: .atomic)
                newItem = ClipboardItem(id: item.id, kind: .image, sourceApp: sourceApp,
                                        imageFileName: fileName, imageHash: hash, pixelSize: pixelSize)
            } catch {
                NSLog("写入图片失败: \(error)")
                return
            }
        case .files(let paths):
            newItem = ClipboardItem(kind: .file, sourceApp: sourceApp, fileURLs: paths)
        }
        newItem.pinned = inheritPinned

        items.insert(newItem, at: 0)
        enforceCapacity()
        scheduleSave()
    }

    // MARK: - 操作

    /// 把某条写回系统剪贴板(供用户随后 ⌘V 粘贴)。
    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let img = image(for: item) {
                pb.writeObjects([img])
            } else if let url = imageURL(for: item), let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }
        case .file:
            let urls = (item.fileURLs ?? []).map { NSURL(fileURLWithPath: $0) }
            if !urls.isEmpty { pb.writeObjects(urls) }
        }
        // 告知监听器:这次变化是我们自己造成的,别记成新条目
        pasteboardWriteHook?()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeItem(at: idx)
        scheduleSave()
    }

    /// 清空全部历史(含置顶)。
    func clearAll() {
        for item in items { deleteImageFileIfNeeded(item) }
        items.removeAll()
        scheduleSave()
    }

    // MARK: - 私有

    private func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        deleteImageFileIfNeeded(items[index])
        items.remove(at: index)
    }

    private func deleteImageFileIfNeeded(_ item: ClipboardItem) {
        guard item.kind == .image, let name = item.imageFileName else { return }
        imageCache.removeObject(forKey: name as NSString)
        thumbCache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    /// 淘汰最旧的非置顶项,直到非置顶数量 <= maxItems。
    private func enforceCapacity() {
        var unpinnedCount = items.filter { !$0.pinned }.count
        guard unpinnedCount > maxItems else { return }
        // 从尾部(最旧)开始删非置顶
        var i = items.count - 1
        while i >= 0 && unpinnedCount > maxItems {
            if !items[i].pinned {
                removeItem(at: i)
                unpinnedCount -= 1
            }
            i -= 1
        }
    }

    private static func dedupKey(for content: CapturedContent) -> (key: String, hash: String?) {
        switch content {
        case .text(let s):
            return ("t:" + s, nil)
        case .image(let data, _):
            let h = ClipboardItem.sha256Hex(data)
            return ("i:" + h, h)
        case .files(let paths):
            return ("f:" + paths.joined(separator: "\n"), nil)
        }
    }

    // MARK: - 持久化

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 立即写盘(退出前可调用)。
    func saveNow() {
        saveWorkItem?.cancel()
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("保存历史失败: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode([ClipboardItem].self, from: data)
            // 丢弃图片文件已丢失的图片条目
            loaded.removeAll { item in
                if item.kind == .image {
                    guard let name = item.imageFileName,
                          FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(name).path)
                    else { return true }
                }
                return false
            }
            items = loaded
        } catch {
            NSLog("加载历史失败: \(error)")
        }
    }
}
