import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
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
        if count == 0 { return "Add repositories and workflows to start monitoring." }
        return "Monitoring \(count) repositor\(count == 1 ? "y" : "ies") quietly in the background."
    }

    @ViewBuilder
    private var content: some View {
        if model.configuration.monitoredRepositories.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.configuration.monitoredRepositories) { repository in
                        RepositoryCard(repository: repository, runs: model.latestRuns)
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
            Text("Configure the repositories and workflow files you care about. The app will stay quiet until state changes matter.")
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
}

private struct RepositoryCard: View {
    var repository: MonitoredRepository
    var runs: [RepositoryWorkflowKey: WorkflowRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(repository.fullName)
                    .font(.headline)
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(repository.fullName)/actions")!)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open Actions in GitHub")
            }

            ForEach(repository.workflows) { workflow in
                let key = RepositoryWorkflowKey(owner: repository.owner, repository: repository.name, workflowIdentifier: workflow.identifier)
                WorkflowRow(workflow: workflow, run: runs[key])
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
}

private struct WorkflowRow: View {
    var workflow: MonitoredWorkflow
    var run: WorkflowRun?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.displayName.isEmpty ? workflow.identifier : workflow.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if workflow.deploymentRelated {
                        Text("Deploy")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Design.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Design.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            Spacer()
            if let url = run?.htmlURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
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
        return "#\(run.runNumber) \(run.effectiveState.label) - \(run.branch)"
    }
}
