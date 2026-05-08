import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var draft: AppConfiguration
    @State private var privateRepoAccess = false

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
                    Text("Securely watch selected workflows without keeping browser tabs open.")
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
            ForEach($draft.monitoredRepositories) { $repository in
                RepositoryEditor(repository: $repository) {
                    draft.monitoredRepositories.removeAll { $0.id == repository.id }
                }
            }
            Button {
                draft.monitoredRepositories.append(MonitoredRepository(owner: draft.defaultOwner, name: "", workflows: [
                    MonitoredWorkflow(identifier: "ci.yml", displayName: "CI")
                ]))
            } label: {
                Label("Add Repository", systemImage: "plus")
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
            Text("The app keeps polling conservative to respect GitHub rate limits and avoid noisy background behavior.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var securitySection: some View {
        SettingsSection(title: "Security", systemImage: "checkmark.shield") {
            Text("Tokens are stored in macOS Keychain with device-only accessibility. Configuration is stored in UserDefaults and never contains tokens. Public repository monitoring can request no OAuth scopes; private repositories require GitHub's `repo` OAuth scope.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct RepositoryEditor: View {
    @Binding var repository: MonitoredRepository
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Owner or organization", text: $repository.owner)
                    .textFieldStyle(.roundedBorder)
                TextField("Repository", text: $repository.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            ForEach($repository.workflows) { $workflow in
                HStack {
                    TextField("Workflow file or ID, e.g. ci.yml", text: $workflow.identifier)
                        .textFieldStyle(.roundedBorder)
                    TextField("Display name", text: $workflow.displayName)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Deploy", isOn: $workflow.deploymentRelated)
                    Button(role: .destructive) {
                        repository.workflows.removeAll { $0.id == workflow.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                repository.workflows.append(MonitoredWorkflow(identifier: "", displayName: ""))
            } label: {
                Label("Add Workflow", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
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
