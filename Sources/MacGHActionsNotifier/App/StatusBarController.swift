import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let appModel: AppModel
    private var latestStatus: AppStatus = .idle
    private var hasUnreadEvents = false
    private var transientStatusTask: Task<Void, Never>?
    private var isShowingTransientStatus = false

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
        configureStatusItem()
        configurePopover()
        appModel.onStatusChanged = { [weak self] status in
            self?.latestStatus = status
            self?.renderSteadyIcon()
        }
        appModel.onWorkflowEvent = { [weak self] status in
            self?.showTransientStatus(status)
        }
        latestStatus = appModel.overallStatus
        renderSteadyIcon()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "GitHub Actions Notifier"
        button.imagePosition = .imageLeading
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: appModel))
    }

    private func showTransientStatus(_ status: AppStatus) {
        hasUnreadEvents = true
        isShowingTransientStatus = true
        transientStatusTask?.cancel()
        render(status: status)
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.isShowingTransientStatus = false
                self.renderSteadyIcon()
            }
        }
    }

    private func renderSteadyIcon() {
        guard !isShowingTransientStatus else { return }
        guard let button = statusItem.button else { return }
        button.image = logoImage(showUnreadDot: hasUnreadEvents)
        button.contentTintColor = nil
        button.toolTip = hasUnreadEvents
            ? "GitHub Actions: unseen events. Latest status: \(latestStatus.title)"
            : "GitHub Actions: \(latestStatus.title)"
    }

    private func render(status: AppStatus) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = status.menuBarTintColor
        button.toolTip = "GitHub Actions: \(status.title)"
    }

    private func logoImage(showUnreadDot: Bool) -> NSImage? {
        let size = NSSize(width: 22, height: 22)
        let output = NSImage(size: size)
        output.lockFocus()

        if let icon = NSImage(named: "AppIcon") {
            icon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        } else if let fallback = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "GitHub Actions Notifier") {
            fallback.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        }

        if showUnreadDot {
            let dotRect = NSRect(x: 14, y: 13, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        hasUnreadEvents = false
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        renderSteadyIcon()
    }
}
