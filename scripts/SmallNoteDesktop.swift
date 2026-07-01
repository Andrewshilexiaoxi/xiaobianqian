import AppKit
import Foundation
import CoreGraphics
import Carbon
import UniformTypeIdentifiers

private let quickHotKeySignature = OSType(0x534E514B)
private let quickHotKeyIdentifier = UInt32(1)

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
    let archivedAt: String?
    let attachments: [NoteAttachment]?
    let title: String?
    let tags: String?
}

struct DeletedBatch: Codable {
    let deletedAt: String
    let reason: String
    let notes: [StickyNote]
}

class EditableDesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class EditableTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = modifiers.contains(.command) && modifiers.subtracting([.command, .shift]).isEmpty

        if commandOnly, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                copy(nil)
                return
            case "x":
                cut(nil)
                return
            case "v":
                paste(nil)
                return
            case "a":
                selectAll(nil)
                return
            case "z":
                if modifiers.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "剪切", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "粘贴", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "全选", action: #selector(selectAll(_:)), keyEquivalent: "")
        return menu
    }
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

    static func appendBlankNote() -> String {
        var notes = load()
        let noteID = UUID().uuidString
        let note = StickyNote(
            id: noteID,
            text: "",
            color: notes.count % 6,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            archivedAt: nil,
            attachments: [],
            title: "快捷便签",
            tags: "#快捷记录 #临时想法 #待整理"
        )
        notes.append(note)
        save(notes)
        return noteID
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

final class NoteCardView: NSView, NSTextViewDelegate {
    let note: StickyNote
    let palette: NSColor
    let expanded: Bool
    weak var bodyTextView: EditableTextView?
    var onDelete: ((String) -> Void)?
    var onArchive: ((String) -> Bool)?
    var onAddAttachments: ((String) -> Void)?
    var onTextChange: ((String, String) -> Void)?

    init(note: StickyNote, color: NSColor, expanded: Bool, height: CGFloat) {
        self.note = note
        self.palette = color
        self.expanded = expanded
        let attachmentCount = min(note.attachments?.count ?? 0, 3)
        let collapsedHeight = CGFloat(174 + (attachmentCount == 0 ? 0 : attachmentCount * 30 + 16))
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: max(collapsedHeight, height)))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        layer?.backgroundColor = palette.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        toolTip = "点按正文即可编辑，修改会自动保存"

        let close = NSButton(title: "删", target: self, action: #selector(deleteSelf))
        close.bezelStyle = .circular
        close.isBordered = false
        close.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        close.contentTintColor = NSColor.black.withAlphaComponent(0.45)
        close.frame = NSRect(x: bounds.width - 34, y: bounds.height - 34, width: 24, height: 24)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(close)

        let isArchived = note.archivedAt != nil
        let archive = NSButton(title: isArchived ? "已存" : "存笔记", target: self, action: #selector(archiveSelf(_:)))
        archive.bezelStyle = .rounded
        archive.isBordered = true
        archive.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        archive.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 0.78)
        archive.frame = NSRect(x: bounds.width - 100, y: bounds.height - 34, width: 58, height: 24)
        archive.autoresizingMask = [.minXMargin, .minYMargin]
        archive.toolTip = "存入 Obsidian 语音笔记"
        archive.isEnabled = !isArchived
        addSubview(archive)

        let addAttachment = NSButton(title: "附件", target: self, action: #selector(addAttachments))
        addAttachment.bezelStyle = .rounded
        addAttachment.isBordered = true
        addAttachment.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addAttachment.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 0.78)
        addAttachment.frame = NSRect(x: bounds.width - 152, y: bounds.height - 34, width: 48, height: 24)
        addAttachment.autoresizingMask = [.minXMargin, .minYMargin]
        addAttachment.toolTip = isArchived ? "已存档的便签不能再添加附件" : "添加图片、PDF 或 Markdown 文件"
        addAttachment.isEnabled = !isArchived
        addSubview(addAttachment)

        let attachments = note.attachments ?? []
        let attachmentHeight = attachments.isEmpty ? CGFloat(0) : CGFloat(min(attachments.count, 3) * 30 + 12)
        let textFrame = NSRect(x: 18, y: 22 + attachmentHeight, width: bounds.width - 36, height: bounds.height - 54 - attachmentHeight)
        let scroll = NSScrollView(frame: textFrame)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = EditableTextView(frame: scroll.bounds)
        textView.string = note.text
        textView.font = NSFont.systemFont(ofSize: 17, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.12, alpha: 0.92)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.toolTip = toolTip
        scroll.documentView = textView
        bodyTextView = textView
        addSubview(scroll)

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

    @objc private func addAttachments() {
        onAddAttachments?(note.id)
    }

    @objc private func openAttachment(_ sender: AttachmentButton) {
        NSWorkspace.shared.open(URL(fileURLWithPath: sender.attachment.path))
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        onTextChange?(note.id, textView.string)
    }

    func focusBody() {
        guard let textView = bodyTextView else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.inputContext?.activate()
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
    var expandedNoteID: String?
    var pendingFocusNoteID: String?
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandlerRef: EventHandlerRef?
    var globalKeyMonitor: Any?
    var localKeyMonitor: Any?
    var lastShortcutTime: Date?

    let colors: [NSColor] = [
        NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.52, alpha: 0.96),
        NSColor(calibratedRed: 0.72, green: 0.91, blue: 0.98, alpha: 0.96),
        NSColor(calibratedRed: 0.83, green: 0.96, blue: 0.75, alpha: 0.96),
        NSColor(calibratedRed: 1.00, green: 0.77, blue: 0.75, alpha: 0.96),
        NSColor(calibratedRed: 0.88, green: 0.80, blue: 1.00, alpha: 0.96),
        NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.62, alpha: 0.96)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installCreateNoteShortcut()
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.render()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef = hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func installCreateNoteShortcut() {
        installEventMonitorFallback()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef = eventRef, let userData = userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr,
                      hotKeyID.signature == quickHotKeySignature else {
                    return noErr
                }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.id == quickHotKeyIdentifier {
                    DispatchQueue.main.async {
                        appDelegate.createBlankNoteFromShortcut()
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &hotKeyHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("小便签快捷键事件处理器注册失败：\(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: quickHotKeySignature, id: quickHotKeyIdentifier)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            NSLog("小便签 Ctrl+2 快捷键注册失败：\(hotKeyStatus)")
            if let hotKeyHandlerRef = hotKeyHandlerRef {
                RemoveEventHandler(hotKeyHandlerRef)
                self.hotKeyHandlerRef = nil
            }
        }
    }

    fileprivate func createBlankNoteFromShortcut() {
        if let lastShortcutTime = lastShortcutTime,
           Date().timeIntervalSince(lastShortcutTime) < 0.35 {
            return
        }
        lastShortcutTime = Date()
        pendingFocusNoteID = NoteStore.appendBlankNote()
        expandedNoteID = nil
        lastNotes = []
        render()
    }

    private func installEventMonitorFallback() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleShortcutEvent(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .control, event.keyCode == 19 else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.createBlankNoteFromShortcut()
        }
        return true
    }

    func render() {
        let notes = NoteStore.load()
        if notes.isEmpty {
            lastNotes = notes
            hideContainerWindow()
            return
        }
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
            hideContainerWindow()
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
            let collapsedHeight = CGFloat(174 + (attachmentCount == 0 ? 0 : attachmentCount * 30 + 16))
            let expanded = note.id == expandedNoteID
            let height = expanded ? expandedHeight(for: note, width: cardWidth, maxHeight: containerHeight) : collapsedHeight
            let column = index / rows
            let row = index % rows
            let x = CGFloat(column) * (cardWidth + gap)
            let collapsedY = containerHeight - collapsedHeight - CGFloat(row) * (slotHeight + gap)
            let y = expanded ? max(CGFloat(0), min(containerHeight - height, collapsedY + collapsedHeight - height)) : collapsedY
            let frame = NSRect(x: x, y: y, width: cardWidth, height: height)

            let view = NoteCardView(note: note, color: colors[note.color % colors.count], expanded: expanded, height: height)
            view.layer?.zPosition = expanded ? 10 : 0
            view.onDelete = { [weak self] id in
                var current = NoteStore.load()
                current.removeAll { $0.id == id }
                NoteStore.save(current)
                DispatchQueue.main.async {
                    if self?.expandedNoteID == id {
                        self?.expandedNoteID = nil
                    }
                    self?.lastNotes = []
                    self?.render()
                }
            }
            view.onTextChange = { [weak self] id, updatedText in
                guard let self = self else { return }
                var current = NoteStore.load()
                guard let noteIndex = current.firstIndex(where: { $0.id == id }) else { return }
                let old = current[noteIndex]
                current[noteIndex] = StickyNote(
                    id: old.id,
                    text: updatedText,
                    color: old.color,
                    createdAt: old.createdAt,
                    archivedAt: old.archivedAt,
                    attachments: old.attachments,
                    title: old.title,
                    tags: old.tags
                )
                NoteStore.save(current)
                self.lastNotes = current
            }
            view.onAddAttachments = { [weak self] id in
                self?.chooseAttachments(for: id)
            }
            view.onArchive = { id in
                let process = Process()
                let cliPath = ProcessInfo.processInfo.environment["XIAOBIANQIAN_CLI"]
                    ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("smallnote").path
                process.executableURL = URL(fileURLWithPath: cliPath)
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

            if note.id == pendingFocusNoteID {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self = self, self.pendingFocusNoteID == note.id else { return }
                    view?.focusBody()
                    self.pendingFocusNoteID = nil
                }
            }
        }

        let window: NSWindow
        if let existing = containerWindow {
            window = existing
            window.setFrame(containerFrame, display: true)
        } else {
            window = EditableDesktopWindow(
                contentRect: containerFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            containerWindow = window
        }
        window.contentView = contentView
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovableByWindowBackground = false

        ensureVisible()
    }

    private func expandedHeight(for note: StickyNote, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let attachmentCount = min(note.attachments?.count ?? 0, 3)
        let attachmentHeight = CGFloat(attachmentCount == 0 ? 0 : attachmentCount * 30 + 16)
        let collapsedHeight = CGFloat(174) + attachmentHeight
        let textWidth = width - 36
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let measured = (note.text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let desired = ceil(measured.height) + attachmentHeight + 82
        return min(max(collapsedHeight, desired), maxHeight)
    }

    private func ensureVisible() {
        guard let window = containerWindow else { return }
        NSApp.unhide(nil)
        window.orderFront(nil)
    }

    private func hideContainerWindow() {
        containerWindow?.contentView = NSView(frame: .zero)
        containerWindow?.orderOut(nil)
        expandedNoteID = nil
        pendingFocusNoteID = nil
    }

    private func chooseAttachments(for noteID: String) {
        let panel = NSOpenPanel()
        panel.title = "添加附件"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf, .plainText, UTType(filenameExtension: "md")!, UTType(filenameExtension: "markdown")!]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var notes = NoteStore.load()
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let note = notes[noteIndex]
        guard note.archivedAt == nil else { return }

        let attachmentDirectory = NoteStore.dataDirectory
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(noteID, isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)

        var attachments = note.attachments ?? []
        for source in panel.urls {
            var destination = attachmentDirectory.appendingPathComponent(source.lastPathComponent)
            var counter = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                let ext = source.pathExtension
                let filename = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
                destination = attachmentDirectory.appendingPathComponent(filename)
                counter += 1
            }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                attachments.append(NoteAttachment(
                    name: destination.lastPathComponent,
                    path: destination.path,
                    type: attachmentType(for: destination)
                ))
            } catch {
                continue
            }
        }

        notes[noteIndex] = StickyNote(
            id: note.id,
            text: note.text,
            color: note.color,
            createdAt: note.createdAt,
            archivedAt: note.archivedAt,
            attachments: attachments,
            title: note.title,
            tags: note.tags
        )
        NoteStore.save(notes)
        lastNotes = []
        render()
    }

    private func attachmentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp":
            return "image"
        case "pdf":
            return "pdf"
        case "md", "markdown":
            return "markdown"
        default:
            return "file"
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
