# Q for Email

Q for Email files non-essential Apple Mail out of the Inbox using an AI endpoint you choose. Important mail stays where it is. Spam, promotions, newsletters, and the other categories you leave on move to mailboxes named `Q Spam`, `Q Promotions`, and so on, so you can check them when you feel like it.

It is an open source menu-bar app from [Cedar Labs](https://cdr.xyz).

## What it will not do

- It does not delete mail.
- It does not send, reply, or forward.
- It does not use Apple's Junk mailbox, so it will not train Mail's junk filter or auto-delete.
- It does not read attachments, and it does not send the full message body.

On Gmail accounts, a mailbox created in Mail usually syncs as a label. The action is a move, so filed mail leaves the Inbox.

## What the model sees

Sender, subject, date, whether a `List-Unsubscribe` header exists, `Precedence`, `Auto-Submitted`, and a 600-character plain-text excerpt. Long links in the excerpt are replaced with `[link]`. The excerpt is wrapped as untrusted data. The API key stays in the Keychain.

A loopback endpoint (`localhost`, `127.0.0.1`) is the private default. Any other host needs an explicit confirmation before the first sort.

## Defaults

- Filing mode is Review. Auto is a switch. Review queues proposed moves until you file them. Auto moves immediately.
- Scope is new mail only, measured from the moment you turn sorting on. Include existing Inbox mail is a switch.
- All six categories start on: Spam, Promotions, Newsletters, Social, Receipts, Notifications. Each is a toggle.
- If the model is unsure, the category is off, or the reply cannot be parsed, the message stays in the Inbox.
- Sorting itself starts off, so installing the app does not touch Mail.

## Install from Homebrew

After the cask is in the tap:

```bash
brew tap cdrxyz/tap
brew install --cask cdrxyz/tap/q-for-email
```

The published build is unsigned Apple Silicon. No Developer ID is required to build the disk image, and none is used. macOS will warn on first launch. Right-click Q for Email in Applications and choose Open, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Q for Email.app"
```

Then allow Q for Email to control Mail in System Settings → Privacy & Security → Automation.

A zip and an unsigned DMG are also attached to each GitHub release.

## Build locally

Requires macOS 14 or later and Xcode 16 or later (this project is developed with Swift 6.3).

```bash
git clone https://github.com/cdrxyz/q-for-email.git
cd q-for-email
swift test
swift build -c release
scripts/assemble-app.sh
open "dist/Q for Email.app"
```

`scripts/make-zip.sh` and `scripts/make-dmg.sh` package that app. The DMG is unsigned on purpose.

## Use

1. Open Mail, then open Q for Email from the menu-bar Q.
2. Paste an OpenAI-compatible base URL and a model id. These all work if the server speaks `/v1/chat/completions`:
   - Ollama: `http://127.0.0.1:11434`
   - LM Studio: `http://127.0.0.1:1234`
   - A hosted `/v1` base, plus an API key if that host requires one
3. Test the endpoint. The test classifies a built-in fixture and does not touch Mail.
4. Turn sorting on. Refresh accounts if you want to leave one out.
5. Sort now. In Review, file or keep each proposal. Undo last filing moves the last Auto or File batch back to the Inbox.
6. Optional: turn on Auto, and an auto-sort interval, if you want it to file without asking. Pause stops the timer. Sort now still works.

Q mailboxes are created on the same account as the message the first time they are needed.

## License

Apache-2.0. See [LICENSE](LICENSE).
