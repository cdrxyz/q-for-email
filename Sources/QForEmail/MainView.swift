import SwiftUI
import QForEmailCore

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Q for Email")
                    .font(.title2)
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top])
            Picker("Section", selection: $section) {
                Text("Review").tag(0)
                Text("Activity").tag(1)
                Text("Settings").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            Group {
                switch section {
                case 0: ReviewPane()
                case 1: ActivityPane()
                default: SettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 680)
        .onAppear { model.bootstrap() }
    }
}

struct ReviewPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Sort now") { Task { await model.sortNow() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                Button("File selected") { Task { await model.file(ids: model.selectedPending) } }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedPending.isEmpty || model.busy)
                Button("File all") { Task { await model.file(ids: Set(model.pending.map(\.id))) } }
                    .buttonStyle(.bordered)
                    .disabled(model.pending.isEmpty || model.busy)
                Button("Keep selected") { model.keep(ids: model.selectedPending) }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedPending.isEmpty)
            }
            .padding(.horizontal)
            if model.pending.isEmpty {
                ContentUnavailableView(
                    "Nothing queued",
                    systemImage: "tray",
                    description: Text("Sort now classifies mail and, in Review, waits for you to file it. Important mail stays in the Inbox.")
                )
            } else {
                List(model.pending, selection: $model.selectedPending) { row in
                    DecisionRow(row: row)
                }
            }
        }
    }
}

struct ActivityPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Undo last filing") { Task { await model.undoLastBatch() } }
                    .buttonStyle(.bordered)
                    .disabled(model.busy)
                Button("Reconsider selected") { model.reconsider(ids: model.selectedRecent) }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedRecent.isEmpty)
            }
            .padding(.horizontal)
            if model.recent.isEmpty {
                ContentUnavailableView("No decisions yet", systemImage: "clock", description: Text("Filed and kept mail shows up here."))
            } else {
                List(model.recent, selection: $model.selectedRecent) { row in
                    DecisionRow(row: row)
                }
            }
        }
    }
}

struct DecisionRow: View {
    var row: DecisionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.subject.isEmpty ? "(no subject)" : row.subject)
                .lineLimit(1)
            Text("\(row.actionLabel) · \(row.sender)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !row.reason.isEmpty {
                Text(row.reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Base URL", text: Binding(
                    get: { model.config.endpointURL },
                    set: { model.setEndpoint($0) }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("Model", text: Binding(
                    get: { model.config.model },
                    set: { model.setModel($0) }
                ))
                .textFieldStyle(.roundedBorder)
                SecureField("API key, optional", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Sent to the model: sender, subject, date, list-unsubscribe, precedence, auto-submitted, and a 600-character excerpt. Not the full body. Not attachments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.endpointIsRemote {
                    Toggle("Allow excerpts to be sent to \(model.endpointHost)", isOn: Binding(
                        get: { model.config.remoteEndpointConfirmed },
                        set: { model.config.remoteEndpointConfirmed = $0; model.saveConfig() }
                    ))
                }
                Button("Test endpoint") { Task { await model.testEndpoint() } }
                    .disabled(model.busy)
            }
            Section("Filing") {
                Toggle("Sorting", isOn: Binding(
                    get: { model.config.sortingEnabled },
                    set: { model.config.sortingEnabled = $0; model.saveConfig() }
                ))
                Picker("Mode", selection: Binding(
                    get: { model.config.filingMode },
                    set: { model.config.filingMode = $0; model.saveConfig() }
                )) {
                    Text("Review").tag(FilingMode.review)
                    Text("Auto").tag(FilingMode.auto)
                }
                .pickerStyle(.segmented)
                Picker("Scope", selection: Binding(
                    get: { model.config.scope },
                    set: { model.config.scope = $0; model.saveConfig() }
                )) {
                    Text("New mail only").tag(MailScope.newOnly)
                    Text("Include existing Inbox").tag(MailScope.includeExisting)
                }
                Toggle("Pause auto-sort", isOn: Binding(
                    get: { model.config.paused },
                    set: { model.config.paused = $0; model.saveConfig() }
                ))
                Picker("Auto-sort", selection: Binding(
                    get: { model.config.autoSortMinutes },
                    set: { model.config.autoSortMinutes = $0; model.saveConfig() }
                )) {
                    Text("Off").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                }
                Stepper(value: Binding(
                    get: { model.config.batchSize },
                    set: { model.config.batchSize = $0; model.saveConfig() }
                ), in: 5...40, step: 5) {
                    Text("Batch size \(model.config.batchSize)")
                }
                HStack {
                    Text("Minimum confidence \(model.config.minimumConfidence, format: .number.precision(.fractionLength(2)))")
                    Slider(value: Binding(
                        get: { model.config.minimumConfidence },
                        set: { model.config.minimumConfidence = $0; model.saveConfig() }
                    ), in: 0.5...0.95, step: 0.05)
                }
                Text("Below that, or if the category is off, the message stays in the Inbox. Q Spam is not Apple Junk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Categories") {
                ForEach(Category.catalog) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { model.config.enabledCategoryIDs.contains(category.id) },
                        set: { model.setCategory(category.id, enabled: $0) }
                    ))
                }
                Text("Filed mail moves to a mailbox named Q plus the category, on the same account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Accounts") {
                Button("Refresh from Mail") { Task { await model.refreshAccounts() } }
                    .disabled(model.busy)
                if model.accounts.isEmpty {
                    Text("Refresh after Mail is open.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.accounts) { account in
                    Toggle(account.account, isOn: Binding(
                        get: { model.isAccountEnabled(account.account) },
                        set: { model.setAccount(account.account, enabled: $0) }
                    ))
                }
            }
            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.config.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                LabeledContent("Version", value: Version.version)
                Text("Q for Email never deletes or sends mail. Cedar Labs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension DecisionRecord {
    var actionLabel: String {
        switch action {
        case "pending": return mailbox.isEmpty ? "Review" : "Review → \(mailbox)"
        case "moved": return "Filed to \(mailbox)"
        case "kept": return "Left in Inbox"
        case "undone": return "Moved back"
        default: return action
        }
    }
}
