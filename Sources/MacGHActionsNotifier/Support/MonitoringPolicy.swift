import Foundation

enum BranchMatcher {
    static func matches(branch: String, patterns: [String]) -> Bool {
        let cleanPatterns = patterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanPatterns.isEmpty else { return true }
        return cleanPatterns.contains { wildcardMatch(value: branch, pattern: $0) }
    }

    private static func wildcardMatch(value: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        let regex = "^\(escaped)$"
        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum QuietHours {
    static func contains(_ date: Date, startHour: Int, endHour: Int, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let start = max(0, min(23, startHour))
        let end = max(0, min(23, endHour))
        if start == end { return false }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}

enum DeploymentClassifier {
    static func isDeployment(run: WorkflowRun, repository: MonitoredRepository) -> Bool {
        let patterns = repository.deploymentWorkflowPatterns
        guard !patterns.isEmpty else { return false }
        return patterns.contains {
            BranchMatcher.matches(branch: run.name, patterns: [$0]) ||
                BranchMatcher.matches(branch: run.displayTitle, patterns: [$0])
        }
    }
}

enum NotificationPolicy {
    static func shouldNotify(
        run: WorkflowRun,
        repository: MonitoredRepository,
        preferences: NotificationPreferences,
        currentUserLogin: String?,
        now: Date
    ) -> Bool {
        if let mutedUntil = repository.mutedUntil, mutedUntil > now {
            return false
        }
        if preferences.quietHoursEnabled,
           QuietHours.contains(now, startHour: preferences.quietHoursStartHour, endHour: preferences.quietHoursEndHour) {
            return false
        }
        if preferences.notifyOnlyForCurrentUser {
            guard let currentUserLogin, let triggeredBy = run.triggeredBy else { return false }
            guard triggeredBy.caseInsensitiveCompare(currentUserLogin) == .orderedSame else { return false }
        }
        return true
    }
}
