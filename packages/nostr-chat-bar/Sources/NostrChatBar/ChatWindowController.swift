import Cocoa
import Foundation
import UserNotifications

enum SearchNavigation {
    static func direction(for command: Selector, shift: Bool) -> Int? {
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            return shift ? -1 : 1
        case #selector(NSResponder.moveDown(_:)):
            return 1
        case #selector(NSResponder.moveUp(_:)):
            return -1
        default:
            return nil
        }
    }
}

final class ChatWindowController: NSWindowController,
    NSTextViewDelegate, NSSearchFieldDelegate
{
    private let daemon: Daemon
    private(set) var rows: [Row] = []
    private let maxHistory: Int

    private let history = ChatHistoryView()
    private let input = ComposeView()
    private let header = NSTextField(labelWithString: "Chat")
    private let status = NSTextField(labelWithString: "connecting…")
    private let dot = NSView()
    private let card = NSVisualEffectView()
    private let replyBar = NSTextField(labelWithString: "")
    private weak var replyRowRef: NSStackView?
    private let search = NSSearchField()
    private let searchCount = NSTextField(labelWithString: "")
    private weak var searchRowRef: NSStackView?
    private var replyTarget: Row? { didSet { updateReplyBar() } }

    private let panelWidth: CGFloat = 760
    private let panelHeight: CGFloat = 620

    var peerName = "Chat" { didSet { header.stringValue = peerName } }
    var onUnreadChanged: ((Int) -> Void)?
    private var unread = 0 { didSet { onUnreadChanged?(unread) } }

    init(daemon: Daemon, maxHistory: Int) {
        self.daemon = daemon
        self.maxHistory = maxHistory
        let w = DropPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.hidesOnDeactivate = false
        w.isMovable = false
        w.animationBehavior = .none  // we drive the slide ourselves
        super.init(window: w)
        w.onCancel = { [weak self] in self?.hide() }
        history.snapshotProvider = { [weak self] in
            self?.rows.map(\.webPayload) ?? []
        }
        history.onAction = { [weak self] action in self?.handle(action) }
        history.mediaPathResolver = { [weak self] id in
            self?.rows.first(where: { $0.id == id })?.image
        }
        history.start()
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    private func build() {
        guard let cv = window?.contentView else { return }

        // Rounded blurred card — the window itself stays clear so the
        // corner radius reads against whatever's behind it.
        card.material = .popover
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            card.topAnchor.constraint(equalTo: cv.topAnchor),
            card.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        header.font = .boldSystemFont(ofSize: 14)
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor

        let hair = NSBox(); hair.boxType = .separator

        let attach = iconButton("paperclip", #selector(pickFile))
        let send = iconButton("paperplane.fill", #selector(sendClicked))
        send.contentTintColor = .controlAccentColor
        send.keyEquivalent = "\r"
        send.keyEquivalentModifierMask = .command

        input.font = .systemFont(ofSize: 13)
        input.isRichText = false
        input.delegate = self
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.drawsBackground = false
        // Let semantic colours follow the panel appearance. The pill can
        // resolve light on macOS, so pinning darkAqua makes typed text
        // white-on-light and hard to read.
        input.textColor = .labelColor
        input.insertionPointColor = .labelColor
        input.typingAttributes[.foregroundColor] = NSColor.labelColor
        input.textContainerInset = NSSize(width: 8, height: 10)
        // Bare NSTextView() ships a 0×0 textContainer that doesn't
        // track the view — glyphs lay out into nothing while the caret
        // still advances, which is the "invisible text" symptom. Wire
        // up the bits NSTextView.scrollableTextView() would have set.
        let huge = CGFloat.greatestFiniteMagnitude
        input.minSize = .zero
        input.maxSize = NSSize(width: huge, height: huge)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = .width
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: huge)
        input.onSend = { [weak self] in self?.doSend() }
        input.onImagePaste = { [weak self] path in
            self?.daemon.send(["cmd": "send-file", "path": path, "unlink": true])
        }
        let inScroll = NSScrollView()
        inScroll.documentView = input
        inScroll.hasVerticalScroller = true
        inScroll.drawsBackground = false
        inScroll.borderType = .noBorder
        // Rounded pill around the compose box — NSBox would draw its
        // own title/stroke, a plain layer-backed view is simpler and
        // we can tint it to read against the blur.
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 18
        pill.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6).cgColor
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor.separatorColor.cgColor
        inScroll.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(inScroll)
        NSLayoutConstraint.activate([
            inScroll.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            inScroll.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            inScroll.topAnchor.constraint(equalTo: pill.topAnchor),
            inScroll.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
        ])

        // ── Search bar (⌘F) ───────────────────────────────────────────
        // The DOM owns message positions now, so hit calculation and
        // scrolling live in the renderer; this field only sends query
        // changes and steps, and shows the counts reported back.
        search.placeholderString = "Search"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.delegate = self
        searchCount.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        searchCount.textColor = .secondaryLabelColor
        let prev = iconButton("chevron.up", #selector(searchPrev), size: 22, pill: false)
        let next = iconButton("chevron.down", #selector(searchNext), size: 22, pill: false)
        let close = iconButton("xmark", #selector(searchClose), size: 22, pill: false)
        let searchRow = NSStackView(views: [search, searchCount, prev, next, close])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 4
        searchRow.isHidden = true
        searchRowRef = searchRow

        let find = iconButton("magnifyingglass", #selector(searchToggle),
                              size: 22, pill: false)
        let headRow = NSStackView(views: [header, status, NSView(), find, dot])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        // ↳-reply context bar above the pill, hidden until set.
        replyBar.font = .systemFont(ofSize: 11)
        replyBar.textColor = .secondaryLabelColor
        replyBar.lineBreakMode = .byTruncatingTail
        replyBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let clear = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill",
                           accessibilityDescription: "clear")!,
            target: self, action: #selector(clearReply))
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        let replyRow = NSStackView(views: [replyBar, clear])
        replyRow.orientation = .horizontal
        replyRow.alignment = .centerY
        replyRow.spacing = 6
        replyRow.isHidden = true
        replyRowRef = replyRow

        let sendRow = NSStackView(views: [pill, attach, send])
        sendRow.orientation = .horizontal
        sendRow.alignment = .centerY
        sendRow.spacing = 10
        pill.heightAnchor.constraint(equalToConstant: 38).isActive = true

        // The WebView scrolls its own document; the stack just hands it
        // the remaining fixed panel space.
        let historyBox = NSView()
        historyBox.setContentHuggingPriority(.defaultLow, for: .vertical)
        historyBox.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        history.setContentHuggingPriority(.defaultLow, for: .vertical)
        history.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        history.translatesAutoresizingMaskIntoConstraints = false
        historyBox.addSubview(history)
        NSLayoutConstraint.activate([
            history.leadingAnchor.constraint(equalTo: historyBox.leadingAnchor),
            history.trailingAnchor.constraint(equalTo: historyBox.trailingAnchor),
            history.topAnchor.constraint(equalTo: historyBox.topAnchor),
            history.bottomAnchor.constraint(equalTo: historyBox.bottomAnchor),
            historyBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        let root = NSStackView(views: [headRow, searchRow, hair, historyBox, replyRow, sendRow])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            root.topAnchor.constraint(equalTo: card.topAnchor),
            root.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    // Round SF-Symbol button — matches the 📎/✈︎ pair in noctalia
    // without pulling in a whole button style.
    private func iconButton(_ symbol: String, _ action: Selector,
                            size: CGFloat = 32, pill: Bool = true) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(), target: self, action: action)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imageScaling = .scaleProportionallyUpOrDown
        b.symbolConfiguration = .init(pointSize: size * 0.5, weight: .regular)
        b.contentTintColor = .secondaryLabelColor
        b.widthAnchor.constraint(equalToConstant: size).isActive = true
        b.heightAnchor.constraint(equalToConstant: size).isActive = true
        b.wantsLayer = true
        b.layer?.cornerRadius = size / 2
        if pill {
            b.layer?.backgroundColor =
                NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        }
        return b
    }

    // MARK: state

    func setRelays(streaming: Bool, up: Int, total: Int, urls: [String]) {
        status.stringValue = streaming ? "connected · \(up)/\(total)" : "offline"
        status.toolTip = urls.joined(separator: "\n")
        let c: NSColor = !streaming ? .systemRed : (up < total ? .systemOrange : .systemGreen)
        dot.layer?.backgroundColor = c.cgColor
    }

    func apply(_ ev: Event) {
        switch ev.kind {
        case "status":
            if let n = ev.name, !n.isEmpty { peerName = n }
            setRelays(streaming: ev.streaming ?? false,
                      up: ev.relaysUp ?? 0, total: ev.relaysTotal ?? 0,
                      urls: ev.relays ?? [])
            if let u = ev.unread { unread = u }
        case "msg":
            guard let m = ev.msg else { return }
            insert(m)
        case "sent":
            guard let id = ev.target else { return }
            if ev.state == "cancelled" {
                rows.removeAll { $0.id == id }
                history.remove(id: id)
            } else { patch(id) { $0.state = "sent"; $0.tries = 0; $0.error = "" } }
        case "retry":
            guard let id = ev.target else { return }
            patch(id) { $0.tries = ev.tries ?? 0; $0.error = ev.text ?? "" }
        case "ack":
            guard let id = ev.target else { return }
            patch(id) { $0.ack = ev.mark ?? "✓" }
        case "img":
            guard let id = ev.target else { return }
            patch(id) { $0.image = ev.image ?? "" }
        case "error":
            status.stringValue = ev.text ?? "error"
            status.textColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.status.textColor = .secondaryLabelColor
            }
        default: break
        }
    }

    private func insert(_ m: Msg) {
        if rows.contains(where: { $0.id == m.id }) { return }
        let r = Row(id: m.id, mine: m.dir == "out", text: m.content, ts: m.ts,
                    ack: m.ack ?? "", image: m.image ?? "",
                    state: m.state ?? "sent", tries: 0,
                    replyTo: m.replyTo ?? "")
        // insert-sort by ts — replay and live interleave
        var i = rows.count
        while i > 0 && rows[i-1].ts > r.ts { i -= 1 }
        rows.insert(r, at: i)
        var trimmed: [String] = []
        if rows.count > maxHistory {
            trimmed = rows.prefix(rows.count - maxHistory).map(\.id)
            rows.removeFirst(rows.count - maxHistory)
        }
        history.upsert(r)
        for id in trimmed { history.remove(id: id) }
        if m.dir == "in" && !(m.read ?? true) {
            unread += 1
            if !(window?.isVisible ?? false) { notify(m.content) }
        }
    }

    // Metadata-only mirror: the renderer patches bubble chrome by ID
    // and never re-renders the body for these fields.
    private func patch(_ id: String, _ f: (inout Row) -> Void) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        f(&rows[i])
        let row = rows[i]
        history.patch(
            id: id,
            fields: [
                "ack": row.ack,
                "state": row.state,
                "tries": row.tries,
                "hasImage": !row.image.isEmpty,
                "error": row.error,
            ])
    }

    // Resolve renderer intents against canonical rows before side effects.
    private func handle(_ action: WebAction) {
        switch action {
        case .ready:
            break  // consumed by ChatHistoryView
        case let .reply(id):
            replyTarget = rows.first { $0.id == id }
        case let .copy(id):
            guard let row = rows.first(where: { $0.id == id }) else { return }
            copyToPasteboard(row.text)
        case let .retry(id):
            guard rows.contains(where: { $0.id == id && $0.allowsDeliveryAction }) else { return }
            daemon.send(["cmd": "retry", "id": id])
        case let .cancel(id):
            guard rows.contains(where: { $0.id == id && $0.allowsDeliveryAction }) else { return }
            daemon.send(["cmd": "cancel", "id": id])
        case let .openLink(url):
            NSWorkspace.shared.open(url)
        case let .openImage(id):
            guard let file = MediaAuthorizer.authorize(
                id: id,
                resolvePath: { [weak self] id in
                    self?.rows.first(where: { $0.id == id })?.image
                })
            else { return }
            NSWorkspace.shared.open(file)
        case let .searchStatus(current, total):
            searchCount.stringValue = total == 0 ? "0" : "\(current)/\(total)"
        }
    }

    private func notify(_ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = peerName
        content.body = body.count > 120 ? String(body.prefix(117)) + "…" : body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "nostr-chat-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            guard let err else { return }
            FileHandle.standardError.write(
                Data("notification failed: \(err.localizedDescription)\n".utf8))
        }
    }

    // MARK: actions

    func toggle() {
        guard let w = window else { return }
        if w.isVisible { hide() } else { present() }
    }

    // Target rect: centred under the menubar of the screen that
    // currently holds the mouse — same "appear where I'm looking"
    // rule as the noctalia panel's withCurrentScreen.
    private func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let w = min(panelWidth, vis.width - 40)
        let h = min(panelHeight, vis.height - 40)
        let x = vis.midX - w / 2
        let y = vis.maxY - h  // visibleFrame already excludes the menubar
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // Animate the card layer, not the window frame: NSVisualEffectView
    // samples the backdrop at the window's on-screen rect, so moving
    // the window mid-animation makes the blur crawl. Parking the
    // window at its final frame and sliding the layer keeps the blur
    // pinned and lets us use a CASpringAnimation for the overshoot
    // that reads as "dropped in", which the linear window animator
    // can't do.
    func present() {
        guard let w = window, let layer = card.layer else { return }
        w.setFrame(targetFrame(), display: false)
        w.alphaValue = 1
        // .accessory apps need an explicit activate or the panel comes
        // up keyless and the first keystroke goes to the app behind.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // AppKit on non-flipped superviews sets the layer geometry
        // flipped — +y is up — so "above the menubar" is +height.
        let off = w.frame.height
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = off
        spring.toValue = 0
        spring.damping = 28
        spring.stiffness = 320
        spring.mass = 0.9
        spring.initialVelocity = 4
        spring.duration = spring.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        // Seed the model layer at the destination before adding the
        // animation — avoids a one-frame flash at y=0 if CA commits
        // between orderFront and add().
        layer.transform = CATransform3DIdentity
        layer.removeAllAnimations()
        layer.add(spring, forKey: "drop")
        layer.add(fade, forKey: "fade")
        w.invalidateShadow()

        w.makeFirstResponder(input)
        unread = 0
        daemon.send(["cmd": "mark-read"])
    }

    func hide() {
        guard let w = window, w.isVisible, let layer = card.layer else { return }
        let off = w.frame.height
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            w.orderOut(nil)
            layer.transform = CATransform3DIdentity
            // present() called NSApp.activate to grab key for the
            // .accessory process; orderOut alone leaves us active with
            // zero windows, so the previously-frontmost app stays
            // unfocused. NSApp.hide hands activation back to it.
            if NSApp.isActive { NSApp.hide(nil) }
        }
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.toValue = off
        slide.duration = 0.16
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        slide.fillMode = .forwards
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: "drop")
        // Fade the window, not the layer — takes the shadow with it so
        // there's no orphaned drop-shadow rectangle for 160ms.
        w.animator().alphaValue = 0
        CATransaction.commit()
    }

    @objc private func sendClicked() { doSend() }
    private func doSend() {
        let t = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var c: [String: Any] = ["cmd": "send", "text": t]
        if let r = replyTarget { c["replyTo"] = r.id }
        daemon.send(c)
        input.string = ""
        replyTarget = nil
    }
    @objc private func clearReply() { replyTarget = nil }

    // MARK: search

    @objc func searchToggle() {
        if searchRowRef?.isHidden == false { searchClose(); return }
        searchRowRef?.isHidden = false
        window?.makeFirstResponder(search)
        searchChanged()
    }
    @objc private func searchClose() {
        search.stringValue = ""
        searchRowRef?.isHidden = true
        searchCount.stringValue = ""
        history.closeSearch()
        window?.makeFirstResponder(input)
    }
    @objc private func searchChanged() {
        let q = search.stringValue
        if q.isEmpty { searchCount.stringValue = "" }
        history.setSearch(query: q)
    }
    @objc private func searchPrev() { step(-1) }
    @objc private func searchNext() { step(1) }
    private func step(_ d: Int) {
        history.stepSearch(d)
    }
    private func updateReplyBar() {
        let on = replyTarget != nil
        replyRowRef?.isHidden = !on
        replyBar.stringValue = on ? "↳ " + snippet(replyTarget!.text, 80) : ""
        if on { window?.makeFirstResponder(input) }
    }
    private func snippet(_ s: String, _ n: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ")
        return t.count > n ? String(t.prefix(n - 1)) + "…" : t
    }
    @objc private func pickFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        // Our panel sits at .floating; a free-standing NSOpenPanel
        // opens at .normal and ends up underneath. Either present as a
        // sheet on our window or temporarily lift its level — the
        // sheet keeps the chat visible behind it and returns focus to
        // the input on dismiss without extra bookkeeping.
        guard let w = window else { return }
        p.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let u = p.url else { return }
            self?.daemon.send(["cmd": "send-file", "path": u.path])
        }
    }

    // Enter sends, Shift+Enter newlines — chat-app convention, matches
    // Panel.qml's handleReturn.
    func textView(_: NSTextView, doCommandBy sel: Selector) -> Bool {
        // Return handling lives in ComposeView.keyDown; only Esc here.
        guard sel == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if replyTarget != nil { replyTarget = nil } else { hide() }
        return true
    }

    func control(_: NSControl, textView _: NSTextView,
                 doCommandBy command: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if let direction = SearchNavigation.direction(for: command, shift: shift) {
            step(direction)
            return true
        }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            searchClose()
            return true
        }
        return false
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// NSTextView subclass so paste interception sits in the responder
/// chain — a `paste:` on the window controller never fires because the
