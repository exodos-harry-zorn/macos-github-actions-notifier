import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let appModel: AppModel
    private var statusObservation: NSKeyValueObservation?

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
        configureStatusItem()
        configurePopover()
        appModel.onStatusChanged = { [weak self] status in
            self?.render(status: status)
        }
        render(status: appModel.overallStatus)
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

    private func render(status: AppStatus) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.accessibilityLabel)
        image?.isTemplate = status.usesTemplateIcon
        button.image = image
        button.contentTintColor = status.menuBarTintColor
        button.toolTip = "GitHub Actions: \(status.title)"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
