import Foundation
import Testing
@testable import QForEmailCore

@Test func ledgerRemembersAndCanForget() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("q-ledger-\(UUID().uuidString).sqlite")
    let ledger = try DecisionLedger(path: url.path)
    let record = DecisionRecord(
        id: 0,
        account: "iCloud",
        messageKey: "<a@b>",
        mailID: 9,
        sender: "News",
        subject: "Weekly",
        category: "newsletters",
        confidence: 0.9,
        reason: "digest",
        action: "pending",
        mailbox: "Q Newsletters",
        sourceMailbox: "INBOX",
        batchID: "",
        createdAt: "2026-11-10T03:00:00Z"
    )
    #expect(try ledger.insertPending(record))
    #expect(try ledger.insertPending(record) == false)
    #expect(ledger.lookup(account: "iCloud", messageKey: "<a@b>")?.action == "pending")
    let pending = ledger.pending()
    #expect(pending.count == 1)
    try ledger.update(ids: [pending[0].id], action: "moved", batchID: "batch-1")
    #expect(ledger.lastMovedBatchID() == "batch-1")
    #expect(ledger.records(batchID: "batch-1", action: "moved").count == 1)
    try ledger.update(ids: [pending[0].id], action: "undone", batchID: "batch-1")
    #expect(ledger.lastMovedBatchID() == nil)
    try ledger.delete(ids: [pending[0].id])
    #expect(ledger.lookup(account: "iCloud", messageKey: "<a@b>") == nil)
}

@Test func configRoundTripOmitsSecrets() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("q-config-\(UUID().uuidString).json")
    let store = ConfigStore(fileURL: url)
    var config = AppConfig.default
    config.endpointURL = "http://127.0.0.1:11434"
    config.model = "gemma"
    config.filingMode = .review
    config.scope = .newOnly
    config.enabledCategoryIDs = Category.defaultEnabledIDs
    config.sortingEnabled = true
    try store.save(config)
    let loaded = try store.load()
    #expect(loaded == config)
    let text = try String(contentsOf: url)
    #expect(!text.contains("apiKey"))
    #expect(!text.contains("secret"))
    #expect(try ConfigStore(fileURL: url.deletingLastPathComponent().appendingPathComponent("missing.json")).load() == .default)
}

@Test func chatClientRetriesJSONModeAndSendsBearerOnlyWhenSet() async throws {
    let poster = ScriptedPoster(results: [
        HTTPResult(status: 400, body: Data("unsupported".utf8)),
        HTTPResult(status: 200, body: Data(#"{"choices":[{"message":{"content":"{\"category\":\"newsletters\",\"confidence\":0.9,\"reason\":\"digest\"}"}}]}"#.utf8))
    ])
    let client = ChatClient(poster: poster)
    let url = try #require(URL(string: "http://127.0.0.1:11434/v1/chat/completions"))
    let text = try await client.complete(url: url, model: "gemma", apiKey: "secret-key", system: "sys", user: "user")
    #expect(text.contains("newsletters"))
    #expect(poster.bodies.count == 2)
    #expect(poster.bodies[0].contains("response_format"))
    #expect(!poster.bodies[1].contains("response_format"))
    #expect(poster.headers[0]["Authorization"] == "Bearer secret-key")
    #expect(poster.bodies[0].contains("\"temperature\":0") || poster.bodies[0].contains("\"temperature\":0.0"))
}

@Test func chatClientOmitsBearerAndDoesNotRetryAuth() async {
    let poster = ScriptedPoster(results: [
        HTTPResult(status: 401, body: Data("no".utf8))
    ])
    let client = ChatClient(poster: poster)
    let url = URL(string: "http://127.0.0.1/v1/chat/completions")!
    await #expect(throws: ChatClientError.badStatus(401, "no")) {
        try await client.complete(url: url, model: "m", apiKey: nil, system: "s", user: "u")
    }
    #expect(poster.bodies.count == 1)
    #expect(poster.headers[0]["Authorization"] == nil)
}

private final class ScriptedPoster: HTTPPosting, @unchecked Sendable {
    var results: [HTTPResult]
    var bodies: [String] = []
    var headers: [[String: String]] = []

    init(results: [HTTPResult]) {
        self.results = results
    }

    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> HTTPResult {
        bodies.append(String(data: body, encoding: .utf8) ?? "")
        self.headers.append(headers)
        return results.removeFirst()
    }
}
