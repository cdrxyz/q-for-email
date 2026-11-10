import Testing
@testable import QForEmailCore

@Test func newslettersAtThresholdMove() {
    let decision = decide(
        classification: Classification(category: "newsletters", confidence: 0.75, reason: "digest"),
        enabledCategoryIDs: Category.defaultEnabledIDs,
        minimumConfidence: 0.75
    )
    #expect(decision == .move(mailbox: "Q Newsletters", reason: "digest"))
}

@Test func importantStaysEvenWhenCertain() {
    let decision = decide(
        classification: Classification(category: "Important", confidence: 1, reason: "a person wrote"),
        enabledCategoryIDs: Category.defaultEnabledIDs,
        minimumConfidence: 0.75
    )
    #expect(decision == .keepInInbox(reason: "a person wrote"))
}

@Test func unknownCategoryStays() {
    let decision = decide(
        classification: Classification(category: "phishing", confidence: 0.99, reason: "looks bad"),
        enabledCategoryIDs: Category.defaultEnabledIDs,
        minimumConfidence: 0.5
    )
    #expect(decision == .keepInInbox(reason: "unknown or disabled category"))
}

@Test func disabledCategoryStays() {
    let decision = decide(
        classification: Classification(category: "social", confidence: 0.95, reason: "a like"),
        enabledCategoryIDs: Category.defaultEnabledIDs.subtracting(["social"]),
        minimumConfidence: 0.5
    )
    #expect(decision == .keepInInbox(reason: "unknown or disabled category"))
}

@Test func lowConfidenceStays() {
    let decision = decide(
        classification: Classification(category: "spam", confidence: 0.74, reason: "maybe"),
        enabledCategoryIDs: Category.defaultEnabledIDs,
        minimumConfidence: 0.75
    )
    #expect(decision == .keepInInbox(reason: "confidence 0.74 below 0.75"))
}

@Test func emptyCategoryStays() {
    let decision = decide(
        classification: Classification(category: "  ", confidence: 1, reason: ""),
        enabledCategoryIDs: Category.defaultEnabledIDs,
        minimumConfidence: 0
    )
    #expect(decision == .keepInInbox(reason: ""))
}

@Test func allSixCategoriesHaveSafeMailboxes() {
    #expect(Category.catalog.count == 6)
    #expect(Category.defaultEnabledIDs.count == 6)
    for category in Category.catalog {
        #expect(category.mailbox == "Q \(category.label)")
        #expect(isSafeMailboxName(category.mailbox))
    }
}

@Test func unsafeMailboxNamesAreRejected() {
    #expect(!isSafeMailboxName("Q"))
    #expect(!isSafeMailboxName("Q Spam/Junk"))
    #expect(!isSafeMailboxName("Inbox"))
    #expect(!isSafeMailboxName("Q Spam; delete"))
}
