import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            updateBanner
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 560)
        .background(Design.background)
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
                .frame(width: 680, height: 720)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.overallStatus.accent.opacity(0.16))
                Image(systemName: model.overallStatus.symbolName)
                    .foregroundStyle(model.overallStatus.accent)
                    .font(.system(size: 24, weight: .semibold))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.overallStatus.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(20)
    }

    private var subtitle: String {
        if let error = model.lastErrorMessage { return error }
        let count = model.configuration.monitoredRepositories.count
        if count == 0 { return "Add repositories to monitor all GitHub Actions activity." }
        return "Monitoring \(count) repositor\(count == 1 ? "y" : "ies") quietly in the background."
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let title = model.softwareUpdateState.bannerTitle,
           let subtitle = model.softwareUpdateState.bannerSubtitle {
            HStack(spacing: 12) {
                Image(systemName: model.softwareUpdateState.canInstallUpdate ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(model.softwareUpdateState.canInstallUpdate ? Design.blue : Design.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if model.softwareUpdateState.canInstallUpdate {
                    Button("Install") {
                        model.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Design.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.blue.opacity(0.08))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.configuration.monitoredRepositories.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !deploymentRuns.isEmpty {
                        DeploymentSection(runs: deploymentRuns)
                    }
                    ForEach(model.configuration.monitoredRepositories) { repository in
                        RepositoryCard(repository: repository, runs: model.recentRuns)
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            AppLogoView(size: 72)
            Text("Ready to watch your builds")
                .font(.title3.weight(.semibold))
            Text("Choose the repositories you care about. Every Actions run in those repositories will be monitored quietly.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
            Button {
                showingSettings = true
            } label: {
                Label("Open Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)

            Spacer()

            if let rateLimitText = model.lastRateLimit?.displayText {
                Text(rateLimitText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("GitHub API rate-limit budget")
            }

            if model.softwareUpdateSettings.canCheckForUpdates {
                Button {
                    model.checkForUpdates()
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                }
            }

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var deploymentRuns: [WorkflowRun] {
        Array(
            model.recentRuns.values
                .flatMap { $0 }
                .filter(\.isDeployment)
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(3)
        )
    }
}

private struct DeploymentSection: View {
    var runs: [WorkflowRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Deployments", systemImage: "shippingbox.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Design.blue)

            ForEach(runs) { run in
                WorkflowRow(run: run)
            }
        }
        .padding(14)
        .background(Design.blue.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Design.blue.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct RepositoryCard: View {
    var repository: MonitoredRepository
    var runs: [RepositoryWorkflowKey: [WorkflowRun]]
    @State private var isExpanded = false

    private var repositoryRuns: [WorkflowRun] {
        let key = RepositoryWorkflowKey.repository(owner: repository.owner, repository: repository.name)
        return runs[key] ?? []
    }

    private var latestRun: WorkflowRun? {
        repositoryRuns.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                } label: {
                    repositoryHeader
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(repository.fullName)/actions")!)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open Actions in GitHub")
            }

            if isExpanded {
                Divider()
                if repositoryRuns.isEmpty {
                    Text("No workflow runs loaded yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(repositoryRuns) { run in
                            WorkflowRow(run: run)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Design.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Design.border, lineWidth: 1)
        )
    }

    private var repositoryHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(for: latestRun))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(repository.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(latestRun.map { WorkflowRunDisplayFormatter.summary(for: $0) } ?? "No run loaded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func statusColor(for run: WorkflowRun?) -> Color {
        switch run?.effectiveState {
        case .running: Design.blue
        case .succeeded: Design.green
        case .failed, .cancelled: Design.red
        case .problem: Design.orange
        case nil: .secondary
        }
    }
}

private struct WorkflowRow: View {
    var run: WorkflowRun?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(run?.name ?? "All Actions")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let failureDetail {
                    Text(failureDetail)
                        .font(.caption)
                        .foregroundStyle(Design.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let pullRequestURL = run?.pullRequests.first?.htmlURL {
                Button {
                    NSWorkspace.shared.open(pullRequestURL)
                } label: {
                    Image(systemName: "arrow.triangle.pull")
                }
                .buttonStyle(.borderless)
                .help("Open pull request")
            }
            if let url = run?.htmlURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.circle")
                }
                .buttonStyle(.borderless)
                .help("Open run")
            }
        }
    }

    private var color: Color {
        switch run?.effectiveState {
        case .running: Design.blue
        case .succeeded: Design.green
        case .failed, .cancelled: Design.red
        case .problem: Design.orange
        case nil: .secondary
        }
    }

    private var detail: String {
        guard let run else { return "No run loaded yet" }
        return WorkflowRunDisplayFormatter.detail(for: run)
    }

    private var failureDetail: String? {
        guard let run else { return nil }
        return WorkflowRunDisplayFormatter.failureDetail(for: run)
    }
}
