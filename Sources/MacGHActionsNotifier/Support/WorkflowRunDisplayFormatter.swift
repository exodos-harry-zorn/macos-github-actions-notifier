import Foundation

enum WorkflowRunDisplayFormatter {
    static func detail(for run: WorkflowRun, now: Date = Date()) -> String {
        var parts = [
            "#\(run.runNumber) \(run.effectiveState.label)",
            run.branch
        ]
        if let pullRequest = run.pullRequests.first {
            let title = pullRequest.title.map { " \($0)" } ?? ""
            parts.append("PR #\(pullRequest.number)\(title)")
        }
        if let triggeredBy = run.triggeredBy?.trimmingCharacters(in: .whitespacesAndNewlines),
           !triggeredBy.isEmpty {
            parts.append("by \(triggeredBy)")
        }
        if let duration = durationText(for: run, now: now) {
            parts.append(duration)
        }
        parts.append(TimestampFormatter.compact(run.updatedAt, now: now))
        return parts.joined(separator: " - ")
    }

    static func summary(for run: WorkflowRun, now: Date = Date()) -> String {
        "\(run.name) \(detail(for: run, now: now))"
    }

    static func failureDetail(for run: WorkflowRun) -> String? {
        guard let failurePreview = run.failurePreview else { return nil }
        return "Failed at \(failurePreview.displayText)"
    }

    private static func durationText(for run: WorkflowRun, now: Date) -> String? {
        let seconds: TimeInterval
        if let durationSeconds = run.durationSeconds {
            seconds = durationSeconds
        } else if run.effectiveState == .running {
            seconds = max(0, now.timeIntervalSince(run.createdAt))
        } else {
            return nil
        }
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
