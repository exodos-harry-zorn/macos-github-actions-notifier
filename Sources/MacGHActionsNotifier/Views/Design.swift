import SwiftUI

enum Design {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let green = Color(red: 0.06, green: 0.62, blue: 0.38)
    static let blue = Color(red: 0.10, green: 0.42, blue: 0.90)
    static let red = Color(red: 0.88, green: 0.18, blue: 0.20)
    static let orange = Color(red: 0.93, green: 0.50, blue: 0.12)
}

extension AppStatus {
    var accent: Color {
        switch self {
        case .idle: .secondary
        case .success: Design.green
        case .running: Design.blue
        case .failed: Design.red
        case .problem: Design.orange
        }
    }
}

extension WorkflowEffectiveState {
    var label: String {
        switch self {
        case .running: "running"
        case .succeeded: "succeeded"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .problem: "needs attention"
        }
    }
}
