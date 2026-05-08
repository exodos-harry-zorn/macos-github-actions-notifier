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
    private var transientEventStatus: AppStatus?
    private let eventStatusDisplayDuration: UInt64 = 300_000_000_000

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
        configureStatusItem()
        configurePopover()
        appModel.onStatusChanged = { [weak self] status in
            self?.latestStatus = status
            self?.renderCurrentIcon()
        }
        appModel.onWorkflowEvent = { [weak self] status in
            self?.showTransientStatus(status)
        }
        latestStatus = appModel.overallStatus
        renderCurrentIcon()
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
        transientEventStatus = status
        transientStatusTask?.cancel()
        renderCurrentIcon()
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.eventStatusDisplayDuration ?? 300_000_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.transientEventStatus = nil
                self.renderCurrentIcon()
            }
        }
    }

    private func renderCurrentIcon() {
        guard let button = statusItem.button else { return }
        if let status = activeMenuBarStatus {
            button.image = statusImage(for: status, showUnreadDot: hasUnreadEvents)
            button.contentTintColor = nil
            button.toolTip = hasUnreadEvents
                ? "GitHub Actions: unseen events. Latest status: \(status.title)"
                : "GitHub Actions: \(status.title)"
        } else {
            button.image = logoImage(showUnreadDot: hasUnreadEvents)
            button.contentTintColor = nil
            button.toolTip = hasUnreadEvents
                ? "GitHub Actions: unseen events. Latest status: \(latestStatus.title)"
                : "GitHub Actions: \(latestStatus.title)"
        }
    }

    private var activeMenuBarStatus: AppStatus? {
        if latestStatus == .running {
            return .running
        }
        return transientEventStatus
    }

    private func statusImage(for status: AppStatus, showUnreadDot: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let output = NSImage(size: size)
        output.lockFocus()

        let circleRect = NSRect(x: 2.5, y: 2.5, width: 17, height: 17)
        (status.menuBarTintColor ?? .labelColor).setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        NSColor.white.setStroke()
        NSColor.white.setFill()
        switch status {
        case .success:
            drawCheckmark()
        case .running:
            drawRunningMark()
        case .failed:
            drawXMark()
        case .problem:
            drawProblemMark()
        case .idle:
            break
        }

        drawUnreadDotIfNeeded(showUnreadDot)

        output.unlockFocus()
        output.isTemplate = false
        return output
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

        drawUnreadDotIfNeeded(showUnreadDot)

        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func drawCheckmark() {
        let path = NSBezierPath()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 7, y: 11))
        path.line(to: NSPoint(x: 10, y: 8))
        path.line(to: NSPoint(x: 15.5, y: 14.5))
        path.stroke()
    }

    private func drawRunningMark() {
        let arc = NSBezierPath()
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        arc.appendArc(withCenter: NSPoint(x: 11, y: 11), radius: 5.2, startAngle: 35, endAngle: 315, clockwise: false)
        arc.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 15.8, y: 15))
        arrow.line(to: NSPoint(x: 16.2, y: 11.6))
        arrow.line(to: NSPoint(x: 13.2, y: 13.2))
        arrow.close()
        arrow.fill()
    }

    private func drawXMark() {
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 8, y: 8))
        path.line(to: NSPoint(x: 14, y: 14))
        path.move(to: NSPoint(x: 14, y: 8))
        path.line(to: NSPoint(x: 8, y: 14))
        path.stroke()
    }

    private func drawProblemMark() {
        let line = NSBezierPath()
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 11, y: 13.8))
        line.line(to: NSPoint(x: 11, y: 9.4))
        line.stroke()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 6.7, width: 2, height: 2)).fill()
    }

    private func drawUnreadDotIfNeeded(_ showUnreadDot: Bool) {
        guard showUnreadDot else { return }
        let dotRect = NSRect(x: 14, y: 13, width: 8, height: 8)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
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
        renderCurrentIcon()
    }
}
