import Foundation
import AppKit
import CryptoKit

/// 剪贴板条目的内容类型。
enum ClipKind: String, Codable {
    case text
    case image
    case file
}

/// 一条剪贴板历史记录。
///
/// 图片不直接进 JSON,而是以 PNG 落盘到 `images/<id>.png`,模型里只保留文件名 +
/// 内容哈希(用于去重)。文本与文件路径直接随模型持久化。
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipKind
    var date: Date
    var pinned: Bool
    var sourceApp: String?

    // 文本载荷
    var text: String?
    // 图片:落盘文件名(相对 images/ 目录)+ 内容哈希
    var imageFileName: String?
    var imageHash: String?
    var pixelSize: String?      // 形如 "1280×720",仅用于展示
    // 文件:文件路径列表
    var fileURLs: [String]?

    init(id: UUID = UUID(),
         kind: ClipKind,
         date: Date = Date(),
         pinned: Bool = false,
         sourceApp: String? = nil,
         text: String? = nil,
         imageFileName: String? = nil,
         imageHash: String? = nil,
         pixelSize: String? = nil,
         fileURLs: [String]? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.pinned = pinned
        self.sourceApp = sourceApp
        self.text = text
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.pixelSize = pixelSize
        self.fileURLs = fileURLs
    }

    /// 去重键:内容相同的条目应被视为同一条(从而移到顶部而非新增)。
    var dedupKey: String {
        switch kind {
        case .text:
            return "t:" + (text ?? "")
        case .image:
            return "i:" + (imageHash ?? imageFileName ?? id.uuidString)
        case .file:
            return "f:" + (fileURLs?.joined(separator: "\n") ?? "")
        }
    }

    /// 列表中展示的主预览文本(单行)。
    var previewText: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let oneLine = t.replacingOccurrences(of: "\n", with: " ⏎ ")
            return oneLine.isEmpty ? "(空白文本)" : oneLine
        case .image:
            return pixelSize.map { "图片  \($0)" } ?? "图片"
        case .file:
            let names = (fileURLs ?? []).map { URL(fileURLWithPath: $0).lastPathComponent }
            if names.isEmpty { return "(文件)" }
            if names.count == 1 { return names[0] }
            return "\(names[0]) 等 \(names.count) 个文件"
        }
    }

    /// 行首的 SF Symbol 图标名。
    var symbolName: String {
        switch kind {
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    // MARK: - 工具

    /// 计算一段数据的十六进制 SHA256,用于图片去重。
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
