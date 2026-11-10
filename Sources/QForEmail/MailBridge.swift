import AppKit
import Foundation
import QForEmailCore

enum MailBridgeError: Error, Equatable {
    case mailNotRunning
    case permissionDenied
    case timeout
    case script(String)
}

enum MailBridge {
    static func isMailRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
    }

    static func listAccounts() async throws -> [MailAccountInbox] {
        let text = try await run(MailScript.listAccounts())
        return MailLineParser.accounts(text)
    }

    static func listInboxMetadata(
        account: String,
        inboxName: String,
        limit: Int,
        newerThan: Date?,
        olderThan: Date?
    ) async throws -> [InboxMetadata] {
        guard let script = MailScript.listInboxMetadata(
            account: account,
            inboxName: inboxName,
            limit: limit,
            newerThan: newerThan,
            olderThan: olderThan
        ) else { throw MailBridgeError.script("Refused to build an inbox query.") }
        return MailLineParser.metadata(try await run(script))
    }

    static func details(
        account: String,
        inboxName: String,
        mailIDs: [Int],
        excerptLimit: Int
    ) async throws -> [MessageDetail] {
        guard !mailIDs.isEmpty else { return [] }
        guard let script = MailScript.messageDetails(
            account: account,
            inboxName: inboxName,
            mailIDs: mailIDs,
            excerptLimit: excerptLimit
        ) else { throw MailBridgeError.script("Refused to build a detail query.") }
        return MailLineParser.details(try await run(script))
    }

    static func move(
        account: String,
        inboxName: String,
        mailbox: String,
        mailIDs: [Int]
    ) async throws -> [Int] {
        guard !mailIDs.isEmpty else { return [] }
        guard let script = MailScript.moveMessages(
            account: account,
            inboxName: inboxName,
            mailbox: mailbox,
            mailIDs: mailIDs
        ) else { throw MailBridgeError.script("Refused to move those messages.") }
        return movedIDs(try await run(script))
    }

    static func moveBack(
        account: String,
        inboxName: String,
        mailbox: String,
        messageIDs: [String]
    ) async throws -> [String] {
        guard let script = MailScript.moveBack(
            account: account,
            inboxName: inboxName,
            mailbox: mailbox,
            messageIDs: messageIDs
        ) else { throw MailBridgeError.script("Refused to undo that batch.") }
        return try await run(script)
            .split(separator: Character(MailScript.recordSeparator), omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func movedIDs(_ text: String) -> [Int] {
        text.split(separator: Character(MailScript.recordSeparator), omittingEmptySubsequences: true)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func run(_ source: String) async throws -> String {
        guard isMailRunning() else { throw MailBridgeError.mailNotRunning }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)
                if let error {
                    let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Mail script failed."
                    if number == -1743 {
                        continuation.resume(throwing: MailBridgeError.permissionDenied)
                    } else {
                        continuation.resume(throwing: MailBridgeError.script(message))
                    }
                    return
                }
                continuation.resume(returning: result?.stringValue ?? "")
            }
        }
    }
}
