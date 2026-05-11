import Foundation

enum WorkflowRunDisplayFormatter {
    static func detail(for run: WorkflowRun, now: Date = Date()) -> String {
        var parts = [
            "#\(run.runNumber) \(run.effectiveState.label)",
            run.branch
        ]
        if let triggeredBy = run.triggeredBy?.trimmingCharacters(in: .whitespacesAndNewlines),
           !triggeredBy.isEmpty {
            parts.append("by \(triggeredBy)")
        }
        parts.append(TimestampFormatter.compact(run.updatedAt, now: now))
        return parts.joined(separator: " - ")
    }

    static func summary(for run: WorkflowRun, now: Date = Date()) -> String {
        "\(run.name) \(detail(for: run, now: now))"
    }
}
