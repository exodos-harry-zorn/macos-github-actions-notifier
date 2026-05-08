import Foundation

enum StatusAggregator {
    static func status(for runs: [WorkflowRun]) -> AppStatus {
        guard !runs.isEmpty else { return .idle }
        if runs.contains(where: { $0.effectiveState == .problem }) { return .problem }
        if runs.contains(where: { $0.effectiveState == .failed || $0.effectiveState == .cancelled }) { return .failed }
        if runs.contains(where: { $0.effectiveState == .running }) { return .running }
        return .success
    }
}
