import AppKit
import MacCompanionCore
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController {
    private let model: CompanionModel
    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var detailContent: DetailContent?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var detailDismissTask: Task<Void, Never>?
    private let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    init(model: CompanionModel) {
        self.model = model
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func showNearMouse(at mouseLocation: NSPoint? = nil) {
        let mouse = mouseLocation ?? NSEvent.mouseLocation

        if panel == nil {
            let rootView = ClipboardHistoryView(
                model: model,
                onSelect: { [weak self] item in
                    self?.model.copyClipboardHistoryItem(item)
                    self?.close()
                },
                onClose: { [weak self] in
                    self?.close()
                },
                onRequestDetail: { [weak self] item in
                    self?.requestDetail(item, at: NSEvent.mouseLocation)
                }
            )
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor

            let containerView = NSView()
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor.clear.cgColor
            containerView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 170, height: 160),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = containerView
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            self.panel = panel
        }

        guard let panel else { return }
        let size = NSSize(width: 170, height: preferredPanelHeight())
        let origin = positionForPanel(size: size, mouse: mouse)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        panel.contentView?.layoutSubtreeIfNeeded()
        if !panel.isVisible {
            panel.orderFrontRegardless()
            installOutsideClickMonitorsAfterTriggerEvent()
        }
    }

    func close() {
        detailDismissTask?.cancel()
        detailDismissTask = nil
        detailPanel?.orderOut(nil)
        detailPanel = nil
        detailContent = nil
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    // MARK: - Detail panel

    private func requestDetail(_ item: ClipboardHistoryItem?, at mouse: NSPoint? = nil) {
        detailDismissTask?.cancel()
        detailDismissTask = nil

        guard let item, needsDetail(item.text) else {
            scheduleDetailDismiss(after: 0.15)
            return
        }
        showDetail(item.text, at: mouse)
    }

    private let availableTextWidth: CGFloat = 126

    private func needsDetail(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.contains("\n") { return true }
        let width = (text as NSString).size(withAttributes: [.font: textFont]).width
        return width > availableTextWidth
    }

    private func showDetail(_ text: String, at mouse: NSPoint? = nil) {
        if detailPanel == nil {
            let content = DetailContent(text: text)
            detailContent = content

            let detailView = ClipboardDetailView(
                content: content,
                onHover: { [weak self] inside in
                    if inside {
                        self?.detailDismissTask?.cancel()
                        self?.detailDismissTask = nil
                    } else {
                        self?.scheduleDetailDismiss(after: 0.4)
                    }
                }
            )
            let hostingView = NSHostingView(rootView: detailView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor

            let containerView = NSView()
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor.clear.cgColor
            containerView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = containerView
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            self.detailPanel = panel
        } else {
            detailContent?.text = text
        }

        guard let detailPanel, panel?.isVisible == true else { return }

        let detailSize = detailSizeForText(text)
        let origin = positionNearMouse(size: detailSize, mouse: mouse)
        detailPanel.setContentSize(detailSize)
        detailPanel.setFrameOrigin(origin)
        detailPanel.contentView?.layoutSubtreeIfNeeded()
        if !detailPanel.isVisible {
            detailPanel.orderFrontRegardless()
        }
    }

    private func scheduleDetailDismiss(after seconds: Double) {
        detailDismissTask?.cancel()
        detailDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            closeDetail()
        }
    }

    private func closeDetail() {
        detailPanel?.orderOut(nil)
    }

    private func detailSizeForText(_ text: String) -> NSSize {
        let maxWidth: CGFloat = 300
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - 24, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textFont]
        )
        return NSSize(width: maxWidth, height: ceil(rect.height) + 28)
    }
}

// MARK: - Outside click monitors

extension ClipboardHistoryPanelController {
    private func installOutsideClickMonitorsAfterTriggerEvent() {
        removeOutsideClickMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.installOutsideClickMonitors()
        }
    }

    private func installOutsideClickMonitors() {
        guard panel?.isVisible == true else { return }
        removeOutsideClickMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            let hitPanel = event.window === panel
            let hitDetail = self.detailPanel != nil && event.window === self.detailPanel
            if !hitPanel && !hitDetail {
                self.close()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}

// MARK: - Layout

extension ClipboardHistoryPanelController {
    private func preferredPanelHeight() -> CGFloat {
        if model.clipboardHistory.isEmpty {
            return 60
        }
        let visibleCount = min(model.clipboardHistory.count, 5)
        return CGFloat(21 + visibleCount * 47)
    }

    private func positionForPanel(size: NSSize, mouse: NSPoint? = nil) -> NSPoint {
        clampToScreen(originNearMouse: mouse ?? NSEvent.mouseLocation, size: size, padding: 8)
    }

    private func positionNearMouse(size: NSSize, mouse: NSPoint? = nil) -> NSPoint {
        clampToScreen(originNearMouse: mouse ?? NSEvent.mouseLocation, size: size, padding: 8)
    }

    private func clampToScreen(originNearMouse mouse: NSPoint, size: NSSize, padding: CGFloat) -> NSPoint {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // Prefer below mouse, fall back to above.
        let dockOffset = max(0, visibleFrame.minY - (screen?.frame.minY ?? 0))
        var opensBelowMouse = true
        var y = mouse.y - size.height - padding + dockOffset
        if y < visibleFrame.minY {
            opensBelowMouse = false
            y = mouse.y + padding
        }
        if !opensBelowMouse {
            y = min(y, visibleFrame.maxY - size.height)
        }
        // Clamp to visible frame (tight to edges)
        y = max(y, visibleFrame.minY)
        y = min(y, visibleFrame.maxY - size.height)

        // Prefer right of mouse, fall back to left
        var x = mouse.x + padding
        if x + size.width > visibleFrame.maxX {
            x = mouse.x - size.width - padding
        }
        x = max(x, visibleFrame.minX)
        x = min(x, visibleFrame.maxX - size.width)

        return NSPoint(x: x, y: y)
    }
}

// MARK: - Observable detail content

@MainActor
final class DetailContent: ObservableObject {
    @Published var text: String

    init(text: String) {
        self.text = text
    }
}

// MARK: - Detail view

private struct ClipboardDetailView: View {
    @ObservedObject var content: DetailContent
    let onHover: (Bool) -> Void

    var body: some View {
        Text(content.text)
            .font(.system(.callout, design: .rounded))
            .textSelection(.enabled)
            .padding(12)
            .frame(minWidth: 100, maxWidth: 300, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .background(MouseTrackingRep(onHover: onHover))
    }
}

private struct MouseTrackingRep: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> MouseTracker {
        MouseTracker(onHover: onHover)
    }

    func updateNSView(_ nsView: MouseTracker, context: Context) {
        nsView.onHover = onHover
    }
}

private final class MouseTracker: NSView {
    var onHover: (Bool) -> Void

    init(onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
    }
}
