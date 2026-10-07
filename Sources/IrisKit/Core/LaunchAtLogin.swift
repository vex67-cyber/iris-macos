import AppKit
import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// 开机自启动。
///
/// - macOS 13+：官方 `SMAppService`
/// - macOS 11 / 12：回退到 `LSSharedFileList`（已废弃但仍可用）
public enum LaunchAtLogin {

    public static var isSupported: Bool { true }

    public static var isEnabled: Bool {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        #endif
        return legacyItemExists()
    }

    /// 需要用户在「系统设置 → 通用 → 登录项」里批准（仅 macOS 13+ 有此状态）。
    public static var requiresApproval: Bool {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        #endif
        return false
    }

    public static var statusDescription: String {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return L10n.s("已开启", "On")
            case .requiresApproval:
                return L10n.s("等待你在「系统设置 → 登录项」中批准", "Waiting for approval in System Settings")
            case .notRegistered:
                return L10n.s("已关闭", "Off")
            case .notFound:
                return L10n.s("不可用（请把 App 放进「应用程序」文件夹）", "Unavailable (move the app to /Applications)")
            @unknown default:
                return L10n.s("未知", "Unknown")
            }
        }
        #endif
        return isEnabled ? L10n.s("已开启", "On") : L10n.s("已关闭", "Off")
    }

    /// 尝试开启 / 关闭，返回错误信息（nil 表示成功）。
    @discardableResult
    public static func set(_ enabled: Bool) -> String? {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        #endif
        return legacySet(enabled)
    }

    /// 打开「登录项」设置面板。
    public static func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.users",
        ]
        for string in candidates {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    // MARK: - macOS 11 / 12 的兼容实现
    //
    // 用 LaunchAgent（~/Library/LaunchAgents）实现，比已废弃的
    // LSSharedFileList 更可靠，且下次登录即生效。

    private static let agentLabel = "com.zlr.iris.loginitem"

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist")
    }

    private static var appURL: URL? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return nil }
        return bundle
    }

    private static func legacyItemExists() -> Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    private static func legacySet(_ enabled: Bool) -> String? {
        if !enabled {
            try? FileManager.default.removeItem(at: agentPlistURL)
            return nil
        }

        guard let appURL else {
            return L10n.s("请先把「明目」拖进「应用程序」文件夹", "Move Iris into /Applications first")
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appURL.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try FileManager.default.createDirectory(at: agentPlistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: agentPlistURL, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
