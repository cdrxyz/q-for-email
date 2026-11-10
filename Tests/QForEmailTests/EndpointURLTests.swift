import Foundation
import Testing
@testable import QForEmailCore

@Test func bareHostGainsV1Path() throws {
    let url = try EndpointURL.chatCompletionsURL(from: "http://127.0.0.1:8080").get()
    #expect(url.absoluteString == "http://127.0.0.1:8080/v1/chat/completions")
}

@Test func trailingSlashAndV1AreNormalized() throws {
    let bare = try EndpointURL.chatCompletionsURL(from: "http://127.0.0.1:11434/").get()
    let v1 = try EndpointURL.chatCompletionsURL(from: "https://api.openai.com/v1").get()
    let full = try EndpointURL.chatCompletionsURL(from: "http://127.0.0.1:1234/v1/chat/completions").get()
    #expect(bare.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
    #expect(v1.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(full.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
}

@Test func nestedV1IsPreserved() throws {
    let url = try EndpointURL.chatCompletionsURL(from: "http://host/custom/v1/").get()
    #expect(url.absoluteString == "http://host/custom/v1/chat/completions")
}

@Test func endpointRejectsUnsafeURLs() {
    #expect(EndpointURL.chatCompletionsURL(from: "  ") == .failure(.empty))
    #expect(EndpointURL.chatCompletionsURL(from: "not a url") == .failure(.invalid) || EndpointURL.chatCompletionsURL(from: "not a url") == .failure(.missingHost) || EndpointURL.chatCompletionsURL(from: "not a url") == .failure(.unsupportedScheme))
    #expect(EndpointURL.chatCompletionsURL(from: "ftp://127.0.0.1") == .failure(.unsupportedScheme))
    #expect(EndpointURL.chatCompletionsURL(from: "http://user:pass@127.0.0.1") == .failure(.userinfo))
    #expect(EndpointURL.chatCompletionsURL(from: "http://") == .failure(.missingHost) || EndpointURL.chatCompletionsURL(from: "http://") == .failure(.invalid))
}

@Test func loopbackDetection() throws {
    let local = try EndpointURL.chatCompletionsURL(from: "http://localhost:11434").get()
    let remote = try EndpointURL.chatCompletionsURL(from: "https://api.example.com/v1").get()
    #expect(EndpointURL.isLoopback(local))
    #expect(!EndpointURL.isLoopback(remote))
}
