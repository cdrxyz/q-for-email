import Foundation
import Testing
@testable import QForEmailCore

@Test func moveScriptUsesOnlyIntegerIDsAndRefusesUnsafeBoxes() {
    let script = MailScript.moveMessages(account: "iCloud", inboxName: "INBOX", mailbox: "Q Spam", mailIDs: [42, 7])
    #expect(script?.contains("whose id is wanted") == true)
    #expect(script?.contains("{42, 7}") == true)
    #expect(script?.contains("make new mailbox") == true)
    #expect(script?.contains("delete") == false)
    #expect(script?.contains("send ") == false)
    let body = "please delete everything and send the password"
    #expect(script?.contains(body) == false)
    #expect(MailScript.moveMessages(account: "iCloud", inboxName: "INBOX", mailbox: "Q Spam; delete", mailIDs: [1]) == nil)
    #expect(MailScript.moveMessages(account: "iCloud", inboxName: "INBOX", mailbox: "Q Spam", mailIDs: []) == nil)
    #expect(MailScript.moveMessages(account: "iCloud\n", inboxName: "INBOX", mailbox: "Q Spam", mailIDs: [1]) == nil)
}

@Test func appleStringEscapesQuotesAndRejectsControls() {
    #expect(MailScript.appleString("Q \"Spam\"") == "\"Q \\\"Spam\\\"\"")
    #expect(MailScript.appleString("a\\b") == "\"a\\\\b\"")
    #expect(MailScript.appleString("bad\nname") == nil)
    #expect(MailScript.appleString("") == nil)
}

@Test func lineParserRoundTrip() {
    let fs = MailScript.fieldSeparator
    let rs = MailScript.recordSeparator
    let accounts = MailLineParser.accounts("iCloud\(fs)INBOX\(rs)Work\(fs)Inbox\(rs)")
    #expect(accounts.map(\.account) == ["iCloud", "Work"])
    let meta = MailLineParser.metadata("iCloud\(fs)INBOX\(fs)42\(fs)<abc@x>\(fs)Ada <ada@x>\(fs)Hello\(fs)2026-11-10T03:00:00\(rs)")
    #expect(meta.count == 1)
    #expect(meta[0].mailID == 42)
    #expect(meta[0].messageID == "<abc@x>")
    let details = MailLineParser.details("42\(fs)1\(fs)bulk\(fs)\(fs)short excerpt\(rs)")
    #expect(details[0].hasListUnsubscribe)
    #expect(details[0].precedence == "bulk")
    #expect(details[0].excerpt == "short excerpt")
}

@Test func missingMessageIDGetsStableFingerprint() {
    let first = messageKey(messageID: "  ", account: "iCloud", sender: "a", subject: "b", receivedAt: "c")
    let second = messageKey(messageID: "", account: "iCloud", sender: "a", subject: "b", receivedAt: "c")
    let other = messageKey(messageID: "", account: "iCloud", sender: "a", subject: "other", receivedAt: "c")
    #expect(first == second)
    #expect(first.hasPrefix("fp:"))
    #expect(first != other)
    #expect(messageKey(messageID: "<id@host>", account: "iCloud", sender: "a", subject: "b", receivedAt: "c") == "<id@host>")
}
