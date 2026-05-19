import AppKit
import ApplicationServices
import MacCompanionCore

final class ClipboardTriggerController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFallbackMonitor: Any?
    private var eventTapCanSwallow = false
    private var lastTriggerAt = Date.distantPast
    private var config = AppConfig.default.clipboardHistory
    private let onTrigger: @MainActor () -> Void
    private let onDiagnostic: @MainActor (String) -> Void

    init(onTrigger: @escaping @MainActor () -> Void, onDiagnostic: @escaping @MainActor (String) -> Void = { _ in }) {
        self.onTrigger = onTrigger
        self.onDiagnostic = onDiagnostic
    }

    deinit {
        stop()
    }

    func configure(_ config: ClipboardHistoryConfig) {
        self.config = config
        stop()
        guard config.isEnabled else {
            diagnose("剪切板触发器已关闭")
            return
        }
        startEventTap()
        if eventTap == nil {
            diagnose("剪切板 CGEventTap 未启动，启用全局监听兜底")
            startGlobalFallbackMonitor()
        } else {
            diagnose("剪切板 CGEventTap 已启动")
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        eventTapCanSwallow = false
        if let globalFallbackMonitor {
            NSEvent.removeMonitor(globalFallbackMonitor)
            self.globalFallbackMonitor = nil
        }
    }

    private func startEventTap() {
        requestEventListeningAccessIfNeeded()
        let mask: Int
        switch config.trigger.mode {
        case .middleMouse:
            mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        case .keyboard:
            mask = 1 << CGEventType.keyDown.rawValue
        }
        if createEventTap(options: .defaultTap, mask: mask) {
            eventTapCanSwallow = true
            return
        }
        diagnose("剪切板可吞事件监听未启动，改用只监听模式")
        if createEventTap(options: .listenOnly, mask: mask) {
            eventTapCanSwallow = false
            startGlobalFallbackMonitor()
        }
    }

    private func createEventTap(options: CGEventTapOptions, mask: Int) -> Bool {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: pointer
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func requestEventListeningAccessIfNeeded() {
        guard !CGPreflightListenEventAccess() else { return }
        diagnose("剪切板需要输入监控权限以监听鼠标中键")
        CGRequestListenEventAccess()
    }

    private func startGlobalFallbackMonitor() {
        globalFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp, .keyDown]) { [weak self] event in
            self?.handleFallback(event)
        }
    }

    private func handleFallback(_ event: NSEvent) {
        switch config.trigger.mode {
        case .middleMouse:
            guard event.type == .otherMouseDown || event.type == .otherMouseUp else { return }
            diagnose("剪切板兜底监听收到鼠标按键：\(event.buttonNumber)")
            guard isMiddleMouseButton(event.buttonNumber) else { return }
            triggerOnce()
        case .keyboard:
            guard event.type == .keyDown else { return }
            guard keyboardEvent(event, matches: config.trigger.keyboardShortcut) else { return }
            diagnose("剪切板兜底监听收到键盘快捷键")
            triggerOnce()
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch config.trigger.mode {
        case .middleMouse:
            guard type == .otherMouseDown || type == .otherMouseUp else { return Unmanaged.passUnretained(event) }
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            diagnose("剪切板 CGEventTap 收到鼠标按键：\(buttonNumber)")
            guard isMiddleMouseButton(Int(buttonNumber)) else { return Unmanaged.passUnretained(event) }
            triggerOnce()
            return config.trigger.swallowMiddleMouseClick && eventTapCanSwallow ? nil : Unmanaged.passUnretained(event)

        case .keyboard:
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            guard keyboardEvent(event, matches: config.trigger.keyboardShortcut) else {
                return Unmanaged.passUnretained(event)
            }
            diagnose("剪切板 CGEventTap 收到键盘快捷键")
            triggerOnce()
            return eventTapCanSwallow ? nil : Unmanaged.passUnretained(event)
        }
    }

    private func isMiddleMouseButton(_ buttonNumber: Int) -> Bool {
        buttonNumber == 2 || buttonNumber == 3
    }

    private func triggerOnce() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.05 else { return }
        lastTriggerAt = now
        let trigger = onTrigger
        Task { @MainActor in
            trigger()
        }
    }

    private func diagnose(_ message: String) {
        let diagnostic = onDiagnostic
        Task { @MainActor in
            diagnostic(message)
        }
    }

    private func keyboardEvent(_ event: CGEvent, matches shortcut: String) -> Bool {
        guard let parsed = ParsedShortcut(shortcut) else { return false }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == parsed.keyCode else { return false }
        let flags = event.flags
        return flags.containsAll(parsed.requiredFlags)
    }

    private func keyboardEvent(_ event: NSEvent, matches shortcut: String) -> Bool {
        guard let parsed = ParsedShortcut(shortcut) else { return false }
        guard event.keyCode == parsed.keyCode else { return false }
        return event.modifierFlags.containsAll(parsed.requiredNSEventFlags)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ClipboardTriggerController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

private struct ParsedShortcut {
    let keyCode: CGKeyCode
    let requiredFlags: CGEventFlags
    let requiredNSEventFlags: NSEvent.ModifierFlags

    init?(_ rawValue: String) {
        let parts = rawValue
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let key = parts.last, let keyCode = Self.keyCodes[key] else {
            return nil
        }
        var flags = CGEventFlags()
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘":
                flags.insert(.maskCommand)
            case "option", "opt", "alt", "⌥":
                flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃":
                flags.insert(.maskControl)
            case "shift", "⇧":
                flags.insert(.maskShift)
            default:
                return nil
            }
        }
        self.keyCode = keyCode
        self.requiredFlags = flags
        self.requiredNSEventFlags = Self.nsEventFlags(from: flags)
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50, "space": 49, "esc": 53,
        "escape": 53, "return": 36, "enter": 36, "tab": 48
    ]

    private static func nsEventFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result = NSEvent.ModifierFlags()
        if flags.contains(.maskCommand) {
            result.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            result.insert(.option)
        }
        if flags.contains(.maskControl) {
            result.insert(.control)
        }
        if flags.contains(.maskShift) {
            result.insert(.shift)
        }
        return result
    }
}

private extension CGEventFlags {
    func containsAll(_ required: CGEventFlags) -> Bool {
        intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]) == required
    }
}

private extension NSEvent.ModifierFlags {
    func containsAll(_ required: NSEvent.ModifierFlags) -> Bool {
        intersection([.command, .option, .control, .shift]) == required
    }
}
