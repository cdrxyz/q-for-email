import Foundation

public struct InboxMetadata: Equatable, Sendable, Identifiable {
    public var account: String
    public var inboxName: String
    public var mailID: Int
    public var messageID: String
    public var sender: String
    public var subject: String
    public var receivedAt: String

    public var id: String { "\(account)|\(mailID)" }

    public init(
        account: String,
        inboxName: String,
        mailID: Int,
        messageID: String,
        sender: String,
        subject: String,
        receivedAt: String
    ) {
        self.account = account
        self.inboxName = inboxName
        self.mailID = mailID
        self.messageID = messageID
        self.sender = sender
        self.subject = subject
        self.receivedAt = receivedAt
    }
}

public struct MessageDetail: Equatable, Sendable {
    public var mailID: Int
    public var hasListUnsubscribe: Bool
    public var precedence: String
    public var autoSubmitted: String
    public var excerpt: String

    public init(mailID: Int, hasListUnsubscribe: Bool, precedence: String, autoSubmitted: String, excerpt: String) {
        self.mailID = mailID
        self.hasListUnsubscribe = hasListUnsubscribe
        self.precedence = precedence
        self.autoSubmitted = autoSubmitted
        self.excerpt = excerpt
    }
}

public struct MailAccountInbox: Equatable, Sendable, Identifiable {
    public var account: String
    public var inboxName: String
    public var id: String { account }

    public init(account: String, inboxName: String) {
        self.account = account
        self.inboxName = inboxName
    }
}

public enum MailLineParser {
    public static func accounts(_ text: String) -> [MailAccountInbox] {
        records(text).compactMap { fields in
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            return MailAccountInbox(account: fields[0], inboxName: fields[1])
        }
    }

    public static func metadata(_ text: String) -> [InboxMetadata] {
        records(text).compactMap { fields in
            guard fields.count >= 7, let mailID = Int(fields[2]), mailID > 0 else { return nil }
            return InboxMetadata(
                account: fields[0],
                inboxName: fields[1],
                mailID: mailID,
                messageID: fields[3],
                sender: fields[4],
                subject: fields[5],
                receivedAt: fields[6]
            )
        }
    }

    public static func details(_ text: String) -> [MessageDetail] {
        records(text).compactMap { fields in
            guard fields.count >= 5, let mailID = Int(fields[0]), mailID > 0 else { return nil }
            return MessageDetail(
                mailID: mailID,
                hasListUnsubscribe: fields[1] == "1",
                precedence: fields[2],
                autoSubmitted: fields[3],
                excerpt: fields[4]
            )
        }
    }

    private static func records(_ text: String) -> [[String]] {
        text.split(separator: Character(MailScript.recordSeparator), omittingEmptySubsequences: true)
            .map { record in
                record.split(separator: Character(MailScript.fieldSeparator), omittingEmptySubsequences: false)
                    .map(String.init)
            }
    }
}
