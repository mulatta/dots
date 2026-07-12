// nostr-chat-bar — macOS menubar frontend for nostr-chatd.
//
// Thin port of the noctalia-shell Panel.qml: same NDJSON-over-unix-socket
// protocol (see daemon/ipc.go), same "daemon is source of truth" model.
// We keep one persistent connection, send a `replay` on every connect,
// and mirror events into a persistent WebKit renderer. Renderer state
// is disposable; quit or relaunch rebuilds it from sqlite.
//
// Deliberately Cocoa, not SwiftUI: small native binary, wrapped by
// home-manager in a tiny .app bundle so macOS has a stable notification
// identity.

import Cocoa
import Carbon.HIToolbox
import Foundation
import UserNotifications

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let daemon: Daemon
    private let chat: ChatWindowController
    private let control: ControlSocketServer

    private let maxHistory: Int
    private var hotkey: EventHotKeyRef?

    init(socket: String, controlSocket: String, maxHistory: Int, autoOpen: Bool) {
        self.maxHistory = maxHistory
        daemon = Daemon(path: socket)
        chat = ChatWindowController(
            daemon: daemon, maxHistory: maxHistory, autoOpen: autoOpen)
        control = ControlSocketServer(path: controlSocket)
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        configureStatusItem(unread: 0)
        configureMainMenu()
        configureNotifications()
        registerHotkey()
        registerFind()
        item.button?.action = #selector(statusClicked(_:))
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        chat.onUnreadChanged = { [weak self] n in
            self?.configureStatusItem(unread: n)
        }

        daemon.onEvent = { [weak self] ev in self?.chat.apply(ev) }
        daemon.onConnect = { [weak self] in
            guard let self else { return }
            self.daemon.send(["cmd": "replay", "n": self.maxHistory])
        }
        daemon.onDisconnect = { [weak self] in
            self?.chat.setRelays(streaming: false, up: 0, total: 0, urls: [])
        }
        daemon.start()

        // Scriptable panel control (screenshot helper, keybinds). The
        // daemon socket already covers message commands; this one only
        // moves the window, so a failure to bind is not fatal.
        control.onCommand = { [weak self] command in
            switch command {
            case .toggle: self?.chat.toggle()
            case .present: self?.chat.present()
            case .hide: self?.chat.hide()
            }
        }
        do {
            try control.start()
        } catch {
            FileHandle.standardError.write(
                Data("nostr-chat-bar: control socket unavailable: \(error)\n".utf8))
        }
    }

    private func configureStatusItem(unread: Int) {
        guard let button = item.button else { return }
        if button.image == nil {
            button.image = loadMenuBarImage()
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
        }
        button.title = unread > 0 ? " \(unread)" : ""
        if button.image == nil {
            button.title = unread > 0 ? "💬 \(unread)" : "💬"
        }
    }

    private func loadMenuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "NoaMenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        guard let ev = NSApp.currentEvent else { return }
        if ev.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: "Open \(chat.peerName)", action: #selector(open), keyEquivalent: "")
                .target = self
            m.addItem(.separator())
            m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = m
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            chat.toggle()
        }
    }
    @objc private func open() { chat.present() }

    private func configureMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "nostr-chat-bar")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit nostr-chat-bar",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo",
                                    action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = main
    }

    private func configureNotifications() {
        guard Bundle.main.bundleIdentifier != nil else {
            FileHandle.standardError.write(
                Data("notifications disabled: run nostr-chat-bar from its .app bundle\n".utf8))
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, err in
            if let err {
                FileHandle.standardError.write(
                    Data("notification authorization failed: \(err.localizedDescription)\n".utf8))
            } else if !granted {
                FileHandle.standardError.write(
                    Data("notification authorization denied for nostr-chat-bar\n".utf8))
            }
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification,
        withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive _: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.chat.present()
            done()
        }
    }

    // ⌘F while the panel is up. The compose NSTextView would otherwise
    // beep on performFindPanelAction:. addLocalMonitor is enough — we
    // only want it when our window is key, not system-wide.
    private func registerFind() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self,
                  e.modifierFlags.contains(.command),
                  e.charactersIgnoringModifiers == "f"
            else { return e }
            self.chat.searchToggle(); return nil
        }
    }

    // Carbon can register the ⌥G global toggle without Accessibility permission.
    private func registerHotkey() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, ud in
            let s = Unmanaged<AppController>.fromOpaque(ud!).takeUnretainedValue()
            DispatchQueue.main.async { s.chat.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x6e63_6862) /* 'nchb' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(optionKey), id,
                            GetEventDispatcherTarget(), 0, &hotkey)
    }
}

// MARK: - main

func defaultSocket() -> String {
    if let x = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"], !x.isEmpty {
        return x + "/nostr-chatd.sock"
    }
    // Match the daemon's Darwin fallback (os.TempDir = confstr).
    var t = NSTemporaryDirectory()
    if t.hasSuffix("/") { t.removeLast() }
    return t + "/nostr-chatd.sock"
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

var socket = defaultSocket()
var controlSocket: String?
var maxHistory = 200
var autoOpen = false
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--socket":
            guard let v = it.next() else { die("missing value for --socket") }
            socket = v
        case "--control-socket":
            guard let v = it.next() else { die("missing value for --control-socket") }
            controlSocket = v
        case "--max-history":
            guard let v = it.next(), let n = Int(v), n > 0 else {
                die("--max-history requires a positive integer")
            }
            maxHistory = n
        case "--auto-open": autoOpen = true
        case "--help", "-h":
            print(
                "usage: nostr-chat-bar [--socket PATH] [--control-socket PATH]"
                    + " [--max-history N] [--auto-open]")
            exit(0)
        default:
            die("unknown option: \(a)")
        }
    }
}
// Same directory convention as the flock: the control socket lives
// beside the daemon socket unless overridden.
let resolvedControlSocket = controlSocket
    ?? (socket as NSString).deletingLastPathComponent + "/nostr-chat-bar-ctl.sock"

// Single-instance guard: a second copy (dev build vs launchd agent)
// would register ⌥G twice and show two 💬 items. flock the socket's
// sibling so the lock scopes to the same daemon we'd be talking to;
// O_EXLOCK|O_NONBLOCK fails fast if held. fd is leaked on purpose —
// the kernel drops the lock when we exit.
do {
    let lock = socket + ".bar.lock"
    let fd = open(lock, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK, 0o600)
    if fd < 0 {
        FileHandle.standardError.write(
            Data("nostr-chat-bar: already running (lock \(lock)): \(String(cString: strerror(errno)))\n".utf8))
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let ctrl = AppController(
    socket: socket, controlSocket: resolvedControlSocket, maxHistory: maxHistory,
    autoOpen: autoOpen)
app.delegate = ctrl
app.run()
