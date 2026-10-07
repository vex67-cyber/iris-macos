import AppKit
import IrisKit

// 明目（Iris）—— 纯 AppKit 生命周期。
//
// 为什么不用 SwiftUI 的 App / Scene：
// - MenuBarExtra 在 macOS 26 上如果用户从控制中心关掉图标会直接终止进程
// - LSUIElement App 用 Settings scene 打开设置窗口会跑到其他 App 后面
// 自己管 NSStatusItem + NSPopover + NSWindow，行为完全可控。
let application = NSApplication.shared
let delegate = IrisAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
