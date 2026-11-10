public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var mailbox: String
    public var hint: String

    public init(id: String, label: String, mailbox: String, hint: String) {
        self.id = id
        self.label = label
        self.mailbox = mailbox
        self.hint = hint
    }

    public static let catalog: [Category] = [
        Category(id: "spam", label: "Spam", mailbox: "Q Spam", hint: "unsolicited junk"),
        Category(id: "promotions", label: "Promotions", mailbox: "Q Promotions", hint: "marketing and sales"),
        Category(id: "newsletters", label: "Newsletters", mailbox: "Q Newsletters", hint: "subscribed digests and list mail"),
        Category(id: "social", label: "Social", mailbox: "Q Social", hint: "social-network notifications"),
        Category(id: "receipts", label: "Receipts", mailbox: "Q Receipts", hint: "orders, shipping, and payment records"),
        Category(id: "notifications", label: "Notifications", mailbox: "Q Notifications", hint: "automated alerts with no decision required")
    ]

    public static let defaultEnabledIDs = Set(catalog.map(\.id))
}

public enum FilingDecision: Equatable, Sendable {
    case keepInInbox(reason: String)
    case move(mailbox: String, reason: String)
}

public func mailboxName(for categoryID: String) -> String? {
    let id = categoryID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let category = Category.catalog.first(where: { $0.id == id }) else { return nil }
    guard isSafeMailboxName(category.mailbox) else { return nil }
    return category.mailbox
}

public func isSafeMailboxName(_ name: String) -> Bool {
    guard name.count <= 64, name.hasPrefix("Q ") else { return false }
    let rest = name.dropFirst(2)
    guard !rest.isEmpty else { return false }
    return rest.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
}

public func decide(
    classification: Classification,
    enabledCategoryIDs: Set<String>,
    minimumConfidence: Double
) -> FilingDecision {
    let category = classification.category
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if category.isEmpty || category == "important" || category == "inbox" {
        return .keepInInbox(reason: classification.reason)
    }
    guard enabledCategoryIDs.contains(category), let mailbox = mailboxName(for: category) else {
        return .keepInInbox(reason: "unknown or disabled category")
    }
    guard classification.confidence >= minimumConfidence else {
        return .keepInInbox(
            reason: "confidence \(classification.confidence) below \(minimumConfidence)"
        )
    }
    return .move(mailbox: mailbox, reason: classification.reason)
}
