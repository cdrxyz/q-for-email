import Foundation

public enum MailScript {
    public static let recordSeparator = "\u{1e}"
    public static let fieldSeparator = "\u{1f}"

    public static func listAccounts() -> String {
        """
        \(helpers)
        tell application "Mail"
          set out to ""
          repeat with acct in accounts
            set acctName to name of acct
            set inboxName to ""
            repeat with candidate in {"INBOX", "Inbox", "inbox"}
              try
                set mb to mailbox candidate of acct
                set inboxName to name of mb
                exit repeat
              end try
            end repeat
            if inboxName is not "" then
              set out to out & qClean(acctName) & FS & qClean(inboxName) & RS
            end if
          end repeat
          return out
        end tell
        """
    }

    public static func listInboxMetadata(
        account: String,
        inboxName: String,
        limit: Int,
        newerThan: Date?,
        olderThan: Date?
    ) -> String? {
        guard let accountLit = appleString(account),
              let inboxLit = appleString(inboxName),
              (1...200).contains(limit)
        else { return nil }
        let lower = dateClause(newerThan, flag: "useLower", name: "lowerDate")
        let upper = dateClause(olderThan, flag: "useUpper", name: "upperDate")
        return """
        \(helpers)
        \(lower.builder)
        \(upper.builder)
        tell application "Mail"
          set theAccount to account \(accountLit)
          set theInbox to mailbox \(inboxLit) of theAccount
          set n to count of messages of theInbox
          set collected to 0
          set out to ""
          repeat with i from n to 1 by -1
            if collected >= \(limit) then exit repeat
            set msg to message i of theInbox
            set rd to date received of msg
            if \(upper.flag) is 1 and rd >= \(upper.name) then
              -- newer than the page cursor
            else if \(lower.flag) is 1 and rd <= \(lower.name) then
              exit repeat
            else
              set mid to id of msg
              set msgid to ""
              try
                set msgid to message id of msg
              end try
              set who to ""
              try
                set who to sender of msg
              end try
              set subj to ""
              try
                set subj to subject of msg
              end try
              set stamp to qISO(rd)
              set out to out & qClean(name of theAccount) & FS & qClean(name of theInbox) & FS & mid & FS & qClean(msgid) & FS & qClean(who) & FS & qClean(subj) & FS & stamp & RS
              set collected to collected + 1
            end if
          end repeat
          return out
        end tell
        """
    }

    public static func messageDetails(
        account: String,
        inboxName: String,
        mailIDs: [Int],
        excerptLimit: Int
    ) -> String? {
        guard let accountLit = appleString(account),
              let inboxLit = appleString(inboxName),
              let idList = integerList(mailIDs),
              (1...2000).contains(excerptLimit)
        else { return nil }
        return """
        \(helpers)
        tell application "Mail"
          set theAccount to account \(accountLit)
          set theInbox to mailbox \(inboxLit) of theAccount
          set idList to \(idList)
          set out to ""
          repeat with wanted in idList
            try
              set msg to first message of theInbox whose id is wanted
              set bodyText to ""
              try
                set bodyText to content of msg as text
              end try
              if length of bodyText > \(excerptLimit) then set bodyText to text 1 thru \(excerptLimit) of bodyText
              set raw to ""
              try
                set raw to all headers of msg
              end try
              set hasUnsub to "0"
              if raw contains "List-Unsubscribe:" then set hasUnsub to "1"
              set prec to qHeaderValue(raw, "Precedence")
              set autos to qHeaderValue(raw, "Auto-Submitted")
              set out to out & wanted & FS & hasUnsub & FS & qClean(prec) & FS & qClean(autos) & FS & qClean(bodyText) & RS
            end try
          end repeat
          return out
        end tell
        """
    }

    public static func moveMessages(
        account: String,
        inboxName: String,
        mailbox: String,
        mailIDs: [Int]
    ) -> String? {
        guard let accountLit = appleString(account),
              let inboxLit = appleString(inboxName),
              let boxLit = appleString(mailbox),
              isSafeMailboxName(mailbox),
              let idList = integerList(mailIDs)
        else { return nil }
        return """
        \(helpers)
        tell application "Mail"
          set theAccount to account \(accountLit)
          tell theAccount
            try
              set dest to mailbox \(boxLit)
            on error
              make new mailbox with properties {name:\(boxLit)}
              set dest to mailbox \(boxLit)
            end try
          end tell
          set theInbox to mailbox \(inboxLit) of theAccount
          set idList to \(idList)
          set out to ""
          repeat with wanted in idList
            try
              set msg to first message of theInbox whose id is wanted
              move msg to dest
              set out to out & wanted & RS
            end try
          end repeat
          return out
        end tell
        """
    }

    public static func moveBack(
        account: String,
        inboxName: String,
        mailbox: String,
        messageIDs: [String]
    ) -> String? {
        guard let accountLit = appleString(account),
              let inboxLit = appleString(inboxName),
              let boxLit = appleString(mailbox),
              isSafeMailboxName(mailbox),
              !messageIDs.isEmpty
        else { return nil }
        let literals = messageIDs.compactMap(appleString)
        guard literals.count == messageIDs.count else { return nil }
        let list = "{" + literals.joined(separator: ", ") + "}"
        return """
        set RS to ASCII character 30
        tell application "Mail"
          set theAccount to account \(accountLit)
          set dest to mailbox \(inboxLit) of theAccount
          set src to mailbox \(boxLit) of theAccount
          set idList to \(list)
          set out to ""
          repeat with wanted in idList
            try
              set msg to first message of src whose message id is wanted
              move msg to dest
              set out to out & wanted & RS
            end try
          end repeat
          return out
        end tell
        """
    }

    public static func appleString(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 200 else { return nil }
        if value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return nil }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func integerList(_ ids: [Int]) -> String? {
        guard !ids.isEmpty, ids.count <= 100, ids.allSatisfy({ $0 > 0 }) else { return nil }
        return "{" + ids.map(String.init).joined(separator: ", ") + "}"
    }

    private static func dateClause(_ date: Date?, flag: String, name: String) -> (builder: String, flag: String, name: String) {
        guard let date else {
            return ("set \(flag) to 0\nset \(name) to current date", flag, name)
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let values = [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second].compactMap { $0 }
        guard values.count == 6, values.allSatisfy({ $0 >= 0 && $0 < 10000 }) else {
            return ("set \(flag) to 0\nset \(name) to current date", flag, name)
        }
        let builder = """
        set \(flag) to 1
        set \(name) to current date
        set year of \(name) to \(values[0])
        set month of \(name) to \(values[1])
        set day of \(name) to \(values[2])
        set hours of \(name) to \(values[3])
        set minutes of \(name) to \(values[4])
        set seconds of \(name) to \(values[5])
        """
        return (builder, flag, name)
    }

    private static let helpers = """
    set FS to ASCII character 31
    set RS to ASCII character 30
    on qClean(t)
      set bad to {ASCII character 30, ASCII character 31, return, linefeed, tab}
      set AppleScript's text item delimiters to bad
      set parts to text items of (t as text)
      set AppleScript's text item delimiters to " "
      set cleaned to parts as text
      set AppleScript's text item delimiters to ""
      return cleaned
    end qClean
    on qPad(n)
      if n < 10 then return "0" & n
      return n as text
    end qPad
    on qISO(d)
      return (year of d as integer as text) & "-" & qPad(month of d as integer) & "-" & qPad(day of d) & "T" & qPad(hours of d) & ":" & qPad(minutes of d) & ":" & qPad(seconds of d)
    end qISO
    on qHeaderValue(raw, key)
      set marker to key & ":"
      if raw does not contain marker then return ""
      set AppleScript's text item delimiters to marker
      set tail to text item 2 of raw
      set AppleScript's text item delimiters to {return, linefeed}
      set lineText to text item 1 of tail
      set AppleScript's text item delimiters to ""
      return lineText
    end qHeaderValue
    """
}
