import Foundation

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
