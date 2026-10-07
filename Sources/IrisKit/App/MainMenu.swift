import AppKit

/// 最小可用的主菜单：让设置窗口在前台时拥有标准的 ⌘, ⌘Q ⌘M 等行为。
enum MainMenu {

    static func install(target: IrisAppDelegate) {
        let main = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        add(appMenu, L10n.s("关于明目", "About Iris"),
            #selector(IrisAppDelegate.menuAbout(_:)), target: target)
        add(appMenu, L10n.s("欢迎引导", "Welcome tour"),
            #selector(IrisAppDelegate.menuWelcome(_:)), target: target)
        appMenu.addItem(.separator())
        add(appMenu, L10n.s("立即休息", "Take a break now"),
            #selector(IrisAppDelegate.menuTakeBreak(_:)), key: "b", target: target,
            modifiers: [.command, .option, .control])
        add(appMenu, L10n.s("暂停 / 恢复提醒", "Pause / Resume reminders"),
            #selector(IrisAppDelegate.menuTogglePause(_:)), key: "p", target: target,
            modifiers: [.command, .option, .control])
        appMenu.addItem(.separator())
        add(appMenu, L10n.s("设置…", "Settings…"),
            #selector(IrisAppDelegate.menuSettings(_:)), key: ",", target: target)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: L10n.s("隐藏明目", "Hide Iris"),
                              action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)

        let quit = NSMenuItem(title: L10n.s("退出明目", "Quit Iris"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)

        // 编辑菜单（让标准编辑快捷键可用）
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: L10n.s("编辑", "Edit"))
        editItem.submenu = editMenu
        add(editMenu, L10n.s("撤销", "Undo"), Selector(("undo:")), key: "z")
        add(editMenu, L10n.s("重做", "Redo"), Selector(("redo:")), key: "Z")
        editMenu.addItem(.separator())
        add(editMenu, L10n.s("剪切", "Cut"), #selector(NSText.cut(_:)), key: "x")
        add(editMenu, L10n.s("拷贝", "Copy"), #selector(NSText.copy(_:)), key: "c")
        add(editMenu, L10n.s("粘贴", "Paste"), #selector(NSText.paste(_:)), key: "v")
        add(editMenu, L10n.s("全选", "Select All"), #selector(NSText.selectAll(_:)), key: "a")

        // 窗口菜单
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: L10n.s("窗口", "Window"))
        windowItem.submenu = windowMenu
        add(windowMenu, L10n.s("最小化", "Minimize"),
            #selector(NSWindow.performMiniaturize(_:)), key: "m")

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @discardableResult
    private static func add(_ menu: NSMenu,
                            _ title: String,
                            _ action: Selector?,
                            key: String = "",
                            target: AnyObject? = nil,
                            modifiers: NSEvent.ModifierFlags? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        if let modifiers { item.keyEquivalentModifierMask = modifiers }
        menu.addItem(item)
        return item
    }
}
