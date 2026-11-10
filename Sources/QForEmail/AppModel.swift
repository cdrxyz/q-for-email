import Foundation
import QForEmailCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig
    @Published var apiKey = ""
    @Published var accounts: [MailAccountInbox] = []
    @Published var pending: [DecisionRecord] = []
    @Published var recent: [DecisionRecord] = []
    @Published var status = "Sorting is off until you turn it on."
    @Published var busy = false
    @Published var selectedPending: Set<Int64> = []
    @Published var selectedRecent: Set<Int64> = []

    private let store: ConfigStore
    private let ledger: DecisionLedger
    private var lastAutoRun: Date?
    private var timerTask: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Q for Email", isDirectory: true)
        store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        config = (try? store.load()) ?? .default
        ledger = (try? DecisionLedger(path: directory.appendingPathComponent("decisions.sqlite").path))
            ?? (try! DecisionLedger(path: NSTemporaryDirectory() + "q-for-email-fallback.sqlite"))
    }

    func bootstrap() {
        apiKey = KeychainStore.load() ?? ""
        reloadLists()
        startTimer()
        if config.sortingEnabled {
            status = config.filingMode == .review ? "Review is on. Sort now queues new mail." : "Auto is on. Sort now files new mail."
        }
    }

    func setEndpoint(_ value: String) {
        if value != config.endpointURL {
            config.verifiedFingerprint = nil
            config.remoteEndpointConfirmed = false
        }
        config.endpointURL = value
        saveConfig()
    }

    func setModel(_ value: String) {
        if value != config.model {
            config.verifiedFingerprint = nil
        }
        config.model = value
        saveConfig()
    }

    func saveConfig() {
        if config.sortingEnabled && config.enabledAt == nil {
            config.enabledAt = Date()
        }
        try? store.save(config)
    }

    func saveKey() {
        try? KeychainStore.save(apiKey)
    }

    func isAccountEnabled(_ name: String) -> Bool {
        !config.disabledAccountNames.contains(name)
    }

    func setAccount(_ name: String, enabled: Bool) {
        if enabled {
            config.disabledAccountNames.remove(name)
        } else {
            config.disabledAccountNames.insert(name)
        }
        saveConfig()
    }

    func setCategory(_ id: String, enabled: Bool) {
        if enabled {
            config.enabledCategoryIDs.insert(id)
        } else {
            config.enabledCategoryIDs.remove(id)
        }
        saveConfig()
    }

    func setLaunchAtLogin(_ on: Bool) {
        config.launchAtLogin = on
        saveConfig()
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            status = "Launch at login needs the app in Applications."
        }
    }

    var endpointIsRemote: Bool {
        guard case let .success(url) = EndpointURL.chatCompletionsURL(from: config.endpointURL) else { return false }
        return !EndpointURL.isLoopback(url)
    }

    var endpointHost: String {
        guard case let .success(url) = EndpointURL.chatCompletionsURL(from: config.endpointURL) else { return "" }
        return url.host ?? ""
    }

    func testEndpoint() async {
        await runBusy {
            saveKey()
            saveConfig()
            let url = try requireEndpoint()
            let snapshot = MessageSnapshot(
                sender: "Digest <news@example.com>",
                subject: "Your weekly briefing",
                receivedAt: "2026-11-10T03:00:00",
                hasListUnsubscribe: true,
                precedence: "bulk",
                autoSubmitted: "no",
                excerpt: "This week's stories. You can unsubscribe at the bottom of the message."
            )
            let text = try await ChatClient(poster: URLSessionHTTPPoster()).complete(
                url: url,
                model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: apiKey.nilIfEmpty,
                system: Classifier.systemPrompt,
                user: Classifier.userPayload(snapshot)
            )
            guard let parsed = Classifier.parse(text) else {
                status = "The model replied, but not with the expected JSON. Nothing was filed."
                return
            }
            config.verifiedFingerprint = endpointFingerprint(url: config.endpointURL, model: config.model)
            saveConfig()
            status = "Test classified the fixture as \(parsed.category). \(parsed.reason)"
        }
    }

    func refreshAccounts() async {
        await runBusy {
            guard MailBridge.isMailRunning() else { throw MailBridgeError.mailNotRunning }
            status = "If macOS asks, allow Q for Email to control Mail."
            accounts = try await MailBridge.listAccounts()
            status = accounts.isEmpty ? "No Inbox mailboxes found." : "Found \(accounts.count) account\(accounts.count == 1 ? "" : "s")."
        }
    }

    func sortNow() async {
        await runBusy {
            guard config.sortingEnabled else {
                status = "Turn sorting on first. New mail is measured from that moment."
                return
            }
            saveKey()
            let url = try requireEndpoint()
            try requireVerified(url)
            guard MailBridge.isMailRunning() else { throw MailBridgeError.mailNotRunning }
            status = "Reading the Inbox. Allow Q for Email to control Mail if macOS asks."
            let found = try await MailBridge.listAccounts()
            accounts = found
            let enabled = found.filter { isAccountEnabled($0.account) }
            guard !enabled.isEmpty else {
                status = "No enabled accounts."
                return
            }
            var candidates: [InboxMetadata] = []
            let newerThan = config.scope == .newOnly ? config.enabledAt : nil
            for account in enabled {
                if candidates.count >= config.batchSize { break }
                let page = try await MailBridge.listInboxMetadata(
                    account: account.account,
                    inboxName: account.inboxName,
                    limit: max(config.batchSize, 40),
                    newerThan: newerThan,
                    olderThan: nil
                )
                for item in page where ledger.lookup(account: item.account, messageKey: messageKey(for: item)) == nil {
                    candidates.append(item)
                    if candidates.count >= config.batchSize { break }
                }
            }
            guard !candidates.isEmpty else {
                status = config.scope == .newOnly ? "No new mail to classify." : "Nothing unclassified in the newest Inbox mail."
                return
            }
            var queued = 0
            var filed = 0
            var kept = 0
            let groups = Dictionary(grouping: candidates) { "\($0.account)\u{1f}\($0.inboxName)" }
            for (_, group) in groups {
                guard let first = group.first else { continue }
                let details = try await MailBridge.details(
                    account: first.account,
                    inboxName: first.inboxName,
                    mailIDs: group.map(\.mailID),
                    excerptLimit: Classifier.excerptLimit
                )
                let byID = Dictionary(uniqueKeysWithValues: details.map { ($0.mailID, $0) })
                var moves: [String: [(InboxMetadata, Classification, String)]] = [:]
                for item in group {
                    let detail = byID[item.mailID]
                    let snapshot = MessageSnapshot(
                        sender: item.sender,
                        subject: item.subject,
                        receivedAt: item.receivedAt,
                        hasListUnsubscribe: detail?.hasListUnsubscribe ?? false,
                        precedence: detail?.precedence ?? "",
                        autoSubmitted: detail?.autoSubmitted ?? "",
                        excerpt: detail?.excerpt ?? ""
                    )
                    let text = try await ChatClient(poster: URLSessionHTTPPoster()).complete(
                        url: url,
                        model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey: apiKey.nilIfEmpty,
                        system: Classifier.systemPrompt,
                        user: Classifier.userPayload(snapshot)
                    )
                    let parsed = Classifier.parse(text) ?? Classification(category: "important", confidence: 0, reason: "unparsed model output")
                    let decision = decide(
                        classification: parsed,
                        enabledCategoryIDs: config.enabledCategoryIDs,
                        minimumConfidence: config.minimumConfidence
                    )
                    switch decision {
                    case .keepInInbox(let reason):
                        try insert(item, category: parsed.category, confidence: parsed.confidence, reason: reason, action: "kept", mailbox: "")
                        kept += 1
                    case .move(let mailbox, let reason):
                        if config.filingMode == .review {
                            try insert(item, category: parsed.category, confidence: parsed.confidence, reason: reason, action: "pending", mailbox: mailbox)
                            queued += 1
                        } else {
                            moves[mailbox, default: []].append((item, parsed, reason))
                        }
                    }
                }
                if config.filingMode == .auto {
                    let batch = UUID().uuidString
                    for (mailbox, rows) in moves {
                        let moved = try await MailBridge.move(
                            account: first.account,
                            inboxName: first.inboxName,
                            mailbox: mailbox,
                            mailIDs: rows.map(\.0.mailID)
                        )
                        let movedSet = Set(moved)
                        for (item, parsed, reason) in rows {
                            let action = movedSet.contains(item.mailID) ? "moved" : "pending"
                            try insert(
                                item,
                                category: parsed.category,
                                confidence: parsed.confidence,
                                reason: reason,
                                action: action,
                                mailbox: mailbox,
                                batchID: action == "moved" ? batch : ""
                            )
                            if action == "moved" { filed += 1 } else { queued += 1 }
                        }
                    }
                }
            }
            reloadLists()
            status = "Queued \(queued), filed \(filed), left \(kept) in the Inbox."
        }
    }

    func file(ids: Set<Int64>) async {
        await runBusy {
            let rows = pending.filter { ids.contains($0.id) && !$0.mailbox.isEmpty }
            guard !rows.isEmpty else { return }
            let batch = UUID().uuidString
            var filed = 0
            let groups = Dictionary(grouping: rows) { "\($0.account)\u{1f}\($0.sourceMailbox)\u{1f}\($0.mailbox)" }
            for (_, group) in groups {
                guard let first = group.first else { continue }
                let moved = try await MailBridge.move(
                    account: first.account,
                    inboxName: first.sourceMailbox,
                    mailbox: first.mailbox,
                    mailIDs: group.map(\.mailID)
                )
                let movedSet = Set(moved)
                let done = group.filter { movedSet.contains($0.mailID) }.map(\.id)
                try ledger.update(ids: done, action: "moved", batchID: batch)
                filed += done.count
            }
            reloadLists()
            status = "Filed \(filed)."
        }
    }

    func keep(ids: Set<Int64>) {
        try? ledger.update(ids: Array(ids), action: "kept", batchID: "")
        reloadLists()
        status = "Left \(ids.count) in the Inbox."
    }

    func reconsider(ids: Set<Int64>) {
        try? ledger.delete(ids: Array(ids))
        reloadLists()
        status = "Those messages can be classified again."
    }

    func undoLastBatch() async {
        await runBusy {
            guard let batch = ledger.lastMovedBatchID() else {
                status = "Nothing to undo."
                return
            }
            let rows = ledger.records(batchID: batch, action: "moved")
            var undone: [Int64] = []
            let groups = Dictionary(grouping: rows) { "\($0.account)\u{1f}\($0.sourceMailbox)\u{1f}\($0.mailbox)" }
            for (_, group) in groups {
                guard let first = group.first else { continue }
                let back = try await MailBridge.moveBack(
                    account: first.account,
                    inboxName: first.sourceMailbox,
                    mailbox: first.mailbox,
                    messageIDs: group.map(\.messageKey).filter { !$0.hasPrefix("fp:") }
                )
                let backSet = Set(back)
                undone.append(contentsOf: group.filter { backSet.contains($0.messageKey) }.map(\.id))
            }
            try ledger.update(ids: undone, action: "undone", batchID: batch)
            reloadLists()
            status = "Moved \(undone.count) back to the Inbox."
        }
    }

    private func insert(
        _ item: InboxMetadata,
        category: String,
        confidence: Double,
        reason: String,
        action: String,
        mailbox: String,
        batchID: String = ""
    ) throws {
        let record = DecisionRecord(
            id: 0,
            account: item.account,
            messageKey: messageKey(for: item),
            mailID: item.mailID,
            sender: item.sender,
            subject: item.subject,
            category: category,
            confidence: confidence,
            reason: reason,
            action: action,
            mailbox: mailbox,
            sourceMailbox: item.inboxName,
            batchID: batchID,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try ledger.insertPending(record)
    }

    private func messageKey(for item: InboxMetadata) -> String {
        QForEmailCore.messageKey(
            messageID: item.messageID,
            account: item.account,
            sender: item.sender,
            subject: item.subject,
            receivedAt: item.receivedAt
        )
    }

    private func requireEndpoint() throws -> URL {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw SetupError("Set a model id.") }
        switch EndpointURL.chatCompletionsURL(from: config.endpointURL) {
        case .success(let url):
            return url
        case .failure:
            throw SetupError("The endpoint URL is not usable.")
        }
    }

    private func requireVerified(_ url: URL) throws {
        let fingerprint = endpointFingerprint(url: config.endpointURL, model: config.model)
        guard config.verifiedFingerprint == fingerprint else {
            throw SetupError("Test the endpoint before sorting.")
        }
        if !EndpointURL.isLoopback(url) && !config.remoteEndpointConfirmed {
            throw SetupError("Confirm that excerpts may be sent to \(url.host ?? "that host").")
        }
    }

    private func reloadLists() {
        pending = ledger.pending()
        recent = ledger.recent()
        selectedPending = selectedPending.intersection(pending.map(\.id))
        selectedRecent = selectedRecent.intersection(recent.map(\.id))
    }

    private func runBusy(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch let error as MailBridgeError {
            status = error.userMessage
        } catch let error as SetupError {
            status = error.message
        } catch let error as ChatClientError {
            status = error.userMessage
        } catch {
            status = error.localizedDescription
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.autoTick()
            }
        }
    }

    private func autoTick() async {
        guard config.sortingEnabled, !config.paused, config.autoSortMinutes > 0, !busy else { return }
        let interval = TimeInterval(config.autoSortMinutes * 60)
        if let lastAutoRun, Date().timeIntervalSince(lastAutoRun) < interval { return }
        lastAutoRun = Date()
        await sortNow()
    }
}

private struct SetupError: Error {
    var message: String
    init(_ message: String) { self.message = message }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension MailBridgeError {
    var userMessage: String {
        switch self {
        case .mailNotRunning:
            return "Open Mail, then try again."
        case .permissionDenied:
            return "Allow Q for Email to control Mail in System Settings, Privacy & Security, Automation."
        case .timeout:
            return "Mail took too long."
        case .script(let message):
            return message
        }
    }
}

private extension ChatClientError {
    var userMessage: String {
        switch self {
        case .badStatus(let status, let body):
            return "The endpoint returned \(status). \(body)"
        case .empty:
            return "The endpoint returned an empty reply."
        case .undecodable:
            return "The endpoint reply was not a chat completion."
        }
    }
}
