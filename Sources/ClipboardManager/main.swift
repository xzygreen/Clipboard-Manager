import AppKit

// 隐藏自测:仅验证存储逻辑(去重 / 移顶 / 容量 / 持久化),不弹任何 UI。
// 用法:./ClipboardManager --selftest
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()   // 内部自行 exit()
}

// 生成 App 图标的 .iconset(供 build.sh 调 iconutil 转 .icns),不启动 UI。
// 用法:./ClipboardManager --makeicon <输出目录.iconset>
if let i = CommandLine.arguments.firstIndex(of: "--makeicon") {
    let outDir = (i + 1 < CommandLine.arguments.count) ? CommandLine.arguments[i + 1] : "ClipboardManager.iconset"
    IconGenerator.writeIconset(to: outDir)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 仅菜单栏,无 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
