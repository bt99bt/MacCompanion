import AppKit
import MacCompanionCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var statusMenuItem: NSMenuItem!
    private let model = CompanionModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model.load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelStatusDidChange),
            name: .companionStatusDidChange,
            object: model
        )
        buildMainMenu()
        buildStatusItem()
        refreshMenuStatus()
        DispatchQueue.main.async { [weak self] in
            self?.openConsole()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openConsole()
        return true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Mac伴侣")
        appMenu.addItem(NSMenuItem(title: "打开控制台", action: #selector(openConsole), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Mac伴侣", action: #selector(quit), keyEquivalent: "q"))
        for item in appMenu.items {
            item.target = self
        }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButtonIcon(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Mac 伴侣")

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "状态：\(model.status)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeFeiniuMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开控制台", action: #selector(openConsole), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func makeFeiniuMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "飞牛", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "飞牛")
        submenu.addItem(NSMenuItem(title: "打开飞牛面板", action: #selector(openFeiniuEmbeddedWeb), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "用浏览器打开", action: #selector(openFeiniuWeb), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "同步内置网页登录态", action: #selector(syncFeiniuToken), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "验证防火墙连接", action: #selector(verifyFeiniu), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "添加当前公网 IP 到白名单", action: #selector(addCurrentIP), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "打开飞牛控制台", action: #selector(openConsole), keyEquivalent: ""))

        for submenuItem in submenu.items {
            submenuItem.target = self
        }
        item.submenu = submenu
        return item
    }

    @objc private func addCurrentIP() {
        Task { @MainActor in
            await model.addCurrentIPToFeiniuFirewall()
        }
    }

    @objc private func openFeiniuWeb() {
        model.openFeiniuWeb()
    }

    @objc private func openFeiniuEmbeddedWeb() {
        openConsole()
        model.presentFeiniuWebLogin()
    }

    @objc private func syncFeiniuToken() {
        Task { @MainActor in
            await model.syncFeiniuTokenFromEmbeddedWeb()
        }
    }

    @objc private func verifyFeiniu() {
        Task { @MainActor in
            await model.verifyFeiniuFirewallConnection()
            openPreferences()
        }
    }

    @objc private func modelStatusDidChange() {
        refreshMenuStatus()
    }

    private func refreshMenuStatus() {
        configureStatusButtonIcon(
            systemSymbolName: model.isWorking ? "clock.arrow.circlepath" : "wrench.and.screwdriver",
            accessibilityDescription: model.isWorking ? "Mac 伴侣正在处理" : "Mac 伴侣"
        )
        statusMenuItem?.title = "状态：\(model.status)"
    }

    private func configureStatusButtonIcon(systemSymbolName: String, accessibilityDescription: String) {
        guard let button = statusItem.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = accessibilityDescription
    }

    @objc private func openConsole() {
        if preferencesWindow == nil {
            let content = PreferencesView(
                model: model,
                openEmbeddedFeiniuWeb: { [weak self] in
                    self?.openFeiniuEmbeddedWeb()
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "我的 Mac 伴侣控制台"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content)
            window.center()
            preferencesWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        if preferencesWindow?.isMiniaturized == true {
            preferencesWindow?.deminiaturize(nil)
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func openPreferences() {
        openConsole()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared

if CommandLine.arguments.contains("--smoke-feiniu") {
    NSApp.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            let model = CompanionModel()
            model.load()
            try await model.ensureFeiniuSession()
            let summary = try await model.feiniuWebSession.fetchFirewallSummary()
            print("MacCompanion Feiniu smoke test passed: profile=\(summary.profile), rules=\(summary.ruleCount), enabled=\(summary.enabled)")
            NSApp.terminate(nil)
        } catch {
            print("MacCompanion Feiniu smoke test failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }
    app.run()
} else {
    final class AppRuntime {
        @MainActor static let shared = AppDelegate()
    }
    app.delegate = AppRuntime.shared
    app.run()
}
