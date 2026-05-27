import AppKit
import Foundation
import CoreGraphics

struct NoteAttachment: Codable, Equatable {
    let name: String
    let path: String
    let type: String
}

struct StickyNote: Codable, Equatable {
    let id: String
    let text: String
    let color: Int
    let createdAt: String
    let attachments: [NoteAttachment]?
}

struct DeletedBatch: Codable {
    let deletedAt: String
    let reason: String
    let notes: [StickyNote]
}

final class NoteStore {
    static var dataDirectory: URL {
        if let configured = ProcessInfo.processInfo.environment["XIAOBIANQIAN_DATA_DIR"],
           !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/xiaobianqian", isDirectory: true)
    }

    static var notesURL: URL {
        dataDirectory.appendingPathComponent("notes.json")
    }

    static var deletedURL: URL {
        dataDirectory.appendingPathComponent("deleted.json")
    }

    static func load() -> [StickyNote] {
        guard let data = try? Data(contentsOf: notesURL) else { return [] }
        return (try? JSONDecoder().decode([StickyNote].self, from: data)) ?? []
    }

    static func save(_ notes: [StickyNote]) {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: notesURL, options: .atomic)
        }
    }

    static func archive(_ notes: [StickyNote], reason: String) {
        guard !notes.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let existing: [DeletedBatch]
        if let data = try? Data(contentsOf: deletedURL),
           let decoded = try? JSONDecoder().decode([DeletedBatch].self, from: data) {
            existing = decoded
        } else {
            existing = []
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let updated = existing + [DeletedBatch(deletedAt: timestamp, reason: reason, notes: notes)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(updated) {
            try? data.write(to: deletedURL, options: .atomic)
        }
    }
}

final class NoteCardView: NSView {
    let note: StickyNote
    let palette: NSColor
    var onDelete: ((String) -> Void)?
    var onArchive: ((String) -> Bool)?

    init(note: StickyNote, color: NSColor) {
        self.note = note
        self.palette = color
        let attachmentCount = min(note.attachments?.count ?? 0, 3)
        let extraHeight = attachmentCount == 0 ? 0 : CGFloat(attachmentCount * 30 + 16)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 174 + extraHeight))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
    }

    private func build() {
        layer?.backgroundColor = palette.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = false

        let close = NSButton(title: "删", target: self, action: #selector(deleteSelf))
        close.bezelStyle = .circular
        close.isBordered = false
        close.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        close.contentTintColor = NSColor.black.withAlphaComponent(0.45)
        close.frame = NSRect(x: bounds.width - 34, y: bounds.height - 34, width: 24, height: 24)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(close)

        let archive = NSButton(title: "存笔记", target: self, action: #selector(archiveSelf(_:)))
        archive.bezelStyle = .rounded
        archive.isBordered = true
        archive.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        archive.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 0.78)
        archive.frame = NSRect(x: bounds.width - 100, y: bounds.height - 34, width: 58, height: 24)
        archive.autoresizingMask = [.minXMargin, .minYMargin]
        archive.toolTip = "存入 Obsidian 语音笔记"
        addSubview(archive)

        let label = NSTextField(labelWithString: note.text)
        let attachments = note.attachments ?? []
        let attachmentHeight = attachments.isEmpty ? CGFloat(0) : CGFloat(min(attachments.count, 3) * 30 + 12)
        label.frame = NSRect(x: 18, y: 22 + attachmentHeight, width: bounds.width - 36, height: bounds.height - 54 - attachmentHeight)
        label.autoresizingMask = [.width, .height]
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 0.92)
        label.font = NSFont.systemFont(ofSize: 17, weight: .regular)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        addSubview(label)

        let date = NSTextField(labelWithString: shortTime(note.createdAt))
        date.frame = NSRect(x: 18, y: bounds.height - 31, width: 120, height: 18)
        date.autoresizingMask = [.maxXMargin, .minYMargin]
        date.textColor = NSColor.black.withAlphaComponent(0.36)
        date.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        addSubview(date)

        for (index, attachment) in attachments.prefix(3).enumerated() {
            let button = AttachmentButton(attachment: attachment)
            button.title = "\(icon(for: attachment.type)) \(attachment.name)"
            button.target = self
            button.action = #selector(openAttachment(_:))
            button.bezelStyle = .rounded
            button.isBordered = true
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.alignment = .left
            button.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 0.82)
            button.frame = NSRect(x: 18, y: 18 + CGFloat(index * 30), width: bounds.width - 36, height: 24)
            button.autoresizingMask = [.width, .minYMargin]
            addSubview(button)
        }
    }

    @objc private func deleteSelf() {
        let alert = NSAlert()
        alert.messageText = "确定删除这条小便签吗？"
        alert.informativeText = "删除后不会保留备份。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDelete?(note.id)
    }

    @objc private func archiveSelf(_ sender: NSButton) {
        if onArchive?(note.id) == true {
            sender.title = "已存"
            sender.isEnabled = false
        }
    }

    @objc private func openAttachment(_ sender: AttachmentButton) {
        NSWorkspace.shared.open(URL(fileURLWithPath: sender.attachment.path))
    }

    private func icon(for type: String) -> String {
        switch type {
        case "image":
            return "图"
        case "pdf":
            return "PDF"
        case "markdown":
            return "MD"
        default:
            return "文件"
        }
    }

    private func shortTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: value) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

final class AttachmentButton: NSButton {
    let attachment: NoteAttachment

    init(attachment: NoteAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var containerWindow: NSWindow?
    var lastNotes: [StickyNote] = []
    var timer: Timer?

    let colors: [NSColor] = [
        NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.52, alpha: 0.96),
        NSColor(calibratedRed: 0.72, green: 0.91, blue: 0.98, alpha: 0.96),
        NSColor(calibratedRed: 0.83, green: 0.96, blue: 0.75, alpha: 0.96),
        NSColor(calibratedRed: 1.00, green: 0.77, blue: 0.75, alpha: 0.96),
        NSColor(calibratedRed: 0.88, green: 0.80, blue: 1.00, alpha: 0.96),
        NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.62, alpha: 0.96)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.render()
        }
    }

    func render() {
        let notes = NoteStore.load()
        if notes == lastNotes {
            ensureVisible()
            return
        }
        lastNotes = notes

        rebuildWindows(for: notes)
    }

    private func rebuildWindows(for notes: [StickyNote]) {
        NSApp.unhide(nil)

        if notes.isEmpty {
            containerWindow?.close()
            containerWindow = nil
            return
        }

        guard let screen = NSScreen.main?.visibleFrame else { return }
        let gap: CGFloat = 18
        let margin: CGFloat = 26
        let cardWidth: CGFloat = 300
        let slotHeight: CGFloat = 300
        let containerHeight = max(slotHeight, screen.height - margin * 2)
        let rows = max(1, Int(containerHeight / (slotHeight + gap)))
        let columns = max(1, Int(ceil(Double(notes.count) / Double(rows))))
        let containerWidth = CGFloat(columns) * cardWidth + CGFloat(max(0, columns - 1)) * gap
        let containerFrame = NSRect(
            x: screen.minX + margin,
            y: screen.maxY - margin - containerHeight,
            width: containerWidth,
            height: containerHeight
        )

        let contentView = NSView(frame: NSRect(origin: .zero, size: containerFrame.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        for (index, note) in notes.enumerated() {
            let attachmentCount = min(note.attachments?.count ?? 0, 3)
            let height = CGFloat(174 + (attachmentCount == 0 ? 0 : attachmentCount * 30 + 16))
            let column = index / rows
            let row = index % rows
            let x = CGFloat(column) * (cardWidth + gap)
            let y = containerHeight - height - CGFloat(row) * (slotHeight + gap)
            let frame = NSRect(x: x, y: y, width: cardWidth, height: height)

            let view = NoteCardView(note: note, color: colors[note.color % colors.count])
            view.onDelete = { [weak self] id in
                var current = NoteStore.load()
                current.removeAll { $0.id == id }
                NoteStore.save(current)
                DispatchQueue.main.async {
                    self?.lastNotes = []
                    self?.render()
                }
            }
            view.onArchive = { id in
                let process = Process()
                let executableDir = Bundle.main.executableURL?.deletingLastPathComponent()
                let bundledScript = executableDir?.appendingPathComponent("smallnote")
                process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XIAOBIANQIAN_CLI"] ?? bundledScript?.path ?? "smallnote")
                process.arguments = ["archive", id]
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0
                } catch {
                    return false
                }
            }
            view.frame = frame
            contentView.addSubview(view)
        }

        let window: NSWindow
        if let existing = containerWindow {
            window = existing
            window.setFrame(containerFrame, display: true)
        } else {
            window = NSWindow(
                contentRect: containerFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            containerWindow = window
        }
        window.contentView = contentView
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()

        ensureVisible()
    }

    private func ensureVisible() {
        guard let window = containerWindow else { return }
        NSApp.unhide(nil)
        window.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
