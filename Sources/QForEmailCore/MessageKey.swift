import CryptoKit
import Foundation

public func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

public func messageKey(messageID: String, account: String, sender: String, subject: String, receivedAt: String) -> String {
    let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return "fp:" + sha256Hex([account, sender, subject, receivedAt].joined(separator: "|"))
}

public func endpointFingerprint(url: String, model: String) -> String {
    sha256Hex(url.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + model.trimmingCharacters(in: .whitespacesAndNewlines))
}
