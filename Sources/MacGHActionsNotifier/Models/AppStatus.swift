import AppKit
import Foundation

enum AppStatus: String, Codable, Equatable {
    case idle
    case success
    case running
    case failed
    case problem

    var title: String {
        switch self {
        case .idle: "Idle"
        case .success: "Succeeded"
        case .running: "Running"
        case .failed: "Failed"
        case .problem: "Needs Attention"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .success: "checkmark.circle.fill"
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        "GitHub Actions \(title)"
    }

    var usesTemplateIcon: Bool {
        self == .idle
    }

    var menuBarTintColor: NSColor? {
        switch self {
        case .idle: nil
        case .success: NSColor.systemGreen
        case .running: NSColor.systemBlue
        case .failed: NSColor.systemRed
        case .problem: NSColor.systemOrange
        }
    }

    static func workflowEventStatus(for state: WorkflowEffectiveState) -> AppStatus {
        switch state {
        case .running: .running
        case .succeeded: .success
        case .failed, .cancelled: .failed
        case .problem: .problem
        }
    }

    static func workflowEventStatus(for kind: WorkflowNotificationKind) -> AppStatus {
        switch kind {
        case .started: .running
        case .succeeded: .success
        case .failed, .cancelled: .failed
        }
    }
}
