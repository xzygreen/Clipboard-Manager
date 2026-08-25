// swift-tools-version:5.9
import PackageDescription

// 注:刻意使用 5.9 工具版本 → 默认 Swift 5 语言模式,
// 以避免 Swift 6 严格并发检查与 AppKit/Timer/Carbon C 回调产生大量隔离报错。
let package = Package(
    name: "ClipboardManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            path: "Sources/ClipboardManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
