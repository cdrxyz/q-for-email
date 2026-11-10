import Foundation
import SQLite3

public struct DecisionRecord: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var account: String
    public var messageKey: String
    public var mailID: Int
    public var sender: String
    public var subject: String
    public var category: String
    public var confidence: Double
    public var reason: String
    public var action: String
    public var mailbox: String
    public var sourceMailbox: String
    public var batchID: String
    public var createdAt: String

    public init(
        id: Int64,
        account: String,
        messageKey: String,
        mailID: Int,
        sender: String,
        subject: String,
        category: String,
        confidence: Double,
        reason: String,
        action: String,
        mailbox: String,
        sourceMailbox: String,
        batchID: String,
        createdAt: String
    ) {
        self.id = id
        self.account = account
        self.messageKey = messageKey
        self.mailID = mailID
        self.sender = sender
        self.subject = subject
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.action = action
        self.mailbox = mailbox
        self.sourceMailbox = sourceMailbox
        self.batchID = batchID
        self.createdAt = createdAt
    }
}

public enum LedgerError: Error, Equatable {
    case open(String)
    case sqlite(String)
}

public final class DecisionLedger: @unchecked Sendable {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty && directory != "." {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw LedgerError.open(lastError())
        }
        try exec("""
        CREATE TABLE IF NOT EXISTS decisions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account TEXT NOT NULL,
          message_key TEXT NOT NULL,
          mail_id INTEGER,
          sender TEXT,
          subject TEXT,
          category TEXT NOT NULL,
          confidence REAL NOT NULL,
          reason TEXT NOT NULL,
          action TEXT NOT NULL,
          mailbox TEXT,
          source_mailbox TEXT,
          batch_id TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(account, message_key)
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    public func lookup(account: String, messageKey: String) -> DecisionRecord? {
        let sql = "SELECT \(columns) FROM decisions WHERE account = ? AND message_key = ? LIMIT 1"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, account)
        bind(stmt, 2, messageKey)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return read(stmt)
    }

    @discardableResult
    public func insertPending(_ record: DecisionRecord) throws -> Bool {
        let sql = """
        INSERT OR IGNORE INTO decisions
        (account, message_key, mail_id, sender, subject, category, confidence, reason, action, mailbox, source_mailbox, batch_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        guard let stmt = prepare(sql) else { throw LedgerError.sqlite(lastError()) }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.account)
        bind(stmt, 2, record.messageKey)
        sqlite3_bind_int64(stmt, 3, Int64(record.mailID))
        bind(stmt, 4, record.sender)
        bind(stmt, 5, record.subject)
        bind(stmt, 6, record.category)
        sqlite3_bind_double(stmt, 7, record.confidence)
        bind(stmt, 8, record.reason)
        bind(stmt, 9, record.action)
        bind(stmt, 10, record.mailbox)
        bind(stmt, 11, record.sourceMailbox)
        bind(stmt, 12, record.batchID)
        bind(stmt, 13, record.createdAt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError()) }
        return sqlite3_changes(db) > 0
    }

    public func pending() -> [DecisionRecord] {
        query("SELECT \(columns) FROM decisions WHERE action = 'pending' ORDER BY id DESC")
    }

    public func recent(limit: Int = 100) -> [DecisionRecord] {
        query("SELECT \(columns) FROM decisions ORDER BY id DESC LIMIT \(max(1, min(limit, 500)))")
    }

    public func lastMovedBatchID() -> String? {
        let sql = "SELECT batch_id FROM decisions WHERE action = 'moved' AND batch_id != '' ORDER BY id DESC LIMIT 1"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        let value = String(cString: text)
        return value.isEmpty ? nil : value
    }

    public func records(batchID: String, action: String) -> [DecisionRecord] {
        let sql = "SELECT \(columns) FROM decisions WHERE batch_id = ? AND action = ? ORDER BY id"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, batchID)
        bind(stmt, 2, action)
        var rows: [DecisionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(read(stmt))
        }
        return rows
    }

    public func update(ids: [Int64], action: String, batchID: String?) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            let sql = "UPDATE decisions SET action = ?, batch_id = ? WHERE id = ?"
            guard let stmt = prepare(sql) else { throw LedgerError.sqlite(lastError()) }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, action)
            bind(stmt, 2, batchID ?? "")
            sqlite3_bind_int64(stmt, 3, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError()) }
        }
    }

    public func delete(ids: [Int64]) throws {
        for id in ids {
            let sql = "DELETE FROM decisions WHERE id = ?"
            guard let stmt = prepare(sql) else { throw LedgerError.sqlite(lastError()) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError()) }
        }
    }

    private let columns = "id, account, message_key, mail_id, sender, subject, category, confidence, reason, action, mailbox, source_mailbox, batch_id, created_at"

    private func query(_ sql: String) -> [DecisionRecord] {
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [DecisionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(read(stmt))
        }
        return rows
    }

    private func read(_ stmt: OpaquePointer?) -> DecisionRecord {
        DecisionRecord(
            id: sqlite3_column_int64(stmt, 0),
            account: column(stmt, 1),
            messageKey: column(stmt, 2),
            mailID: Int(sqlite3_column_int64(stmt, 3)),
            sender: column(stmt, 4),
            subject: column(stmt, 5),
            category: column(stmt, 6),
            confidence: sqlite3_column_double(stmt, 7),
            reason: column(stmt, 8),
            action: column(stmt, 9),
            mailbox: column(stmt, 10),
            sourceMailbox: column(stmt, 11),
            batchID: column(stmt, 12),
            createdAt: column(stmt, 13)
        )
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: text)
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastError()
            sqlite3_free(error)
            throw LedgerError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        _ = value.withCString { cString in
            sqlite3_bind_text(stmt, index, cString, -1, transient)
        }
    }

    private func lastError() -> String {
        guard let db, let text = sqlite3_errmsg(db) else { return "sqlite" }
        return String(cString: text)
    }
}
