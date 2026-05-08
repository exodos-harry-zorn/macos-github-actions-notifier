import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var draft: AppConfiguration
    @State private var privateRepoAccess = false
    @State private var selectedRepositoryID: Int64?

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AppLogoView(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Actions Notifier")
                        .font(.title2.weight(.semibold))
                    Text("Securely watch selected repositories without keeping Actions tabs open.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    model.saveConfiguration(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    authSection
                    repositoriesSection
                    notificationsSection
                    pollingSection
                    securitySection
                }
                .padding(24)
            }
        }
        .background(Design.background)
    }

    private var authSection: some View {
        SettingsSection(title: "Authentication", systemImage: "lock.shield") {
            TextField("GitHub OAuth client ID", text: $draft.githubClientID)
                .textFieldStyle(.roundedBorder)
            TextField("Default account or organization", text: $draft.defaultOwner)
                .textFieldStyle(.roundedBorder)
            Toggle("Request private repository access (`repo` scope)", isOn: $privateRepoAccess)
            HStack {
                Button {
                    model.saveConfiguration(draft)
                    Task { await model.beginDeviceAuthorization(privateRepoAccess: privateRepoAccess) }
                } label: {
                    Label(model.isAuthenticated ? "Sign in again" : "Sign in with GitHub", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
                .tint(Design.green)

                if model.deviceFlow != nil {
                    Button {
                        Task { await model.completeDeviceAuthorization() }
                    } label: {
                        Label("I authorized in browser", systemImage: "checkmark.seal")
                    }
                }

                if model.isAuthenticated {
                    Button(role: .destructive) {
                        model.logout()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            if let flow = model.deviceFlow {
                Text("Enter code \(flow.userCode) at GitHub, then return here.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Design.green)
            }
            if let error = model.lastErrorMessage {
                Text(error)
                    .foregroundStyle(Design.orange)
            }
        }
    }

    private var repositoriesSection: some View {
        SettingsSection(title: "Repositories", systemImage: "shippingbox") {
            HStack {
                Button {
                    model.saveConfiguration(draft)
                    Task { await model.loadAvailableRepositories(owner: draft.defaultOwner) }
                } label: {
                    Label(model.isLoadingRepositories ? "Loading" : "Load repositories", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingRepositories || !model.isAuthenticated)

                if !model.isAuthenticated {
                    Text("Sign in first to load repositories.")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Repository", selection: $selectedRepositoryID) {
                Text("Choose a repository").tag(Int64?.none)
                ForEach(model.availableRepositories) { repository in
                    Text(repositoryLabel(repository))
                        .tag(Int64?.some(repository.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(model.availableRepositories.isEmpty)

            Button {
                addSelectedRepository()
            } label: {
                Label("Monitor selected repository", systemImage: "plus")
            }
            .disabled(selectedRepositoryID == nil)

            if let message = model.repositoryLoadMessage {
                Text(message)
                    .foregroundStyle(Design.orange)
            }

            if draft.monitoredRepositories.isEmpty {
                Text("Selected repositories will monitor all GitHub Actions runs. No workflow file configuration is needed.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(draft.monitoredRepositories) { repository in
                        SelectedRepositoryRow(repository: repository) {
                            draft.monitoredRepositories.removeAll { $0.id == repository.id }
                        }
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications", systemImage: "bell.badge") {
            Toggle("Workflow started", isOn: $draft.notificationPreferences.notifyOnStarted)
            Toggle("Workflow succeeded", isOn: $draft.notificationPreferences.notifyOnSucceeded)
            Toggle("Workflow failed", isOn: $draft.notificationPreferences.notifyOnFailed)
            Toggle("Workflow cancelled", isOn: $draft.notificationPreferences.notifyOnCancelled)
        }
    }

    private var pollingSection: some View {
        SettingsSection(title: "Refresh", systemImage: "clock.arrow.circlepath") {
            Stepper(value: $draft.pollingIntervalSeconds, in: 60...900, step: 30) {
                Text("Poll every \(Int(draft.pollingIntervalSeconds)) seconds")
            }
            Stepper(value: $draft.recentRunsPerRepository, in: 1...20, step: 1) {
                Text("Show \(draft.recentRunsPerRepository) recent run\(draft.recentRunsPerRepository == 1 ? "" : "s") per repository")
            }
            Text("The app keeps polling conservative to respect GitHub rate limits and avoid noisy background behavior.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var securitySection: some View {
        SettingsSection(title: "Security", systemImage: "checkmark.shield") {
            Text("GitHub tokens and the OAuth Client ID are stored in macOS Keychain with device-only accessibility. Configuration is stored in UserDefaults and never contains GitHub credentials. Public repository monitoring can request no OAuth scopes; private repositories require GitHub's `repo` OAuth scope.")
                .foregroundStyle(.secondary)
            Text("License: Apache License 2.0. The app is provided as open source software without warranties.")
                .foregroundStyle(.secondary)
        }
    }

    private func repositoryLabel(_ repository: GitHubRepository) -> String {
        repository.isPrivate ? "\(repository.fullName) (private)" : repository.fullName
    }

    private func addSelectedRepository() {
        guard let selectedRepositoryID,
              let repository = model.availableRepositories.first(where: { $0.id == selectedRepositoryID }) else {
            return
        }
        let parts = repository.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        guard !draft.monitoredRepositories.contains(where: { $0.owner == parts[0] && $0.name == parts[1] }) else {
            return
        }
        draft.monitoredRepositories.append(MonitoredRepository(owner: parts[0], name: parts[1], workflows: []))
        self.selectedRepositoryID = nil
    }
}

private struct SelectedRepositoryRow: View {
    var repository: MonitoredRepository
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(Design.green)
            Text(repository.fullName)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("All Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Design.blue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Design.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Design.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
