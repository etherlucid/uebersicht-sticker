import AppKit
import Foundation

struct MenuState: Codable {
    var mode: String?              // "PLUS_CLICK" or "CONTEXT_MENU" or "PICK_ONLY" or "MANAGER"
    var instanceId: String?
    var currentSticker: String?    // relative path e.g. "sticker.widget/stickers/cat.webp" or nil
    var scale: Double?
    var flipped: Bool?
    var isPaused: Bool?
    var audioSync: Bool?
    var opacity: Double?
    var shadow: Bool?
    var enableSnapping: Bool?
    var x: Int?
    var y: Int?
}

struct StickerItem {
    let filename: String
    let title: String
    let relPath: String
    let image: NSImage?
    let isInUse: Bool
}

class MenuDelegate: NSObject {
    var outputAction: String?

    @objc func handleItem(_ sender: NSMenuItem) {
        outputAction = sender.representedObject as? String
    }
}

func chooseWebPFile() -> String? {
    let script = """
    tell application "System Events"
        activate
        try
            set f to choose file of type {"org.webmproject.webp", "webp"} with prompt "Select a WebP Sticker"
            return POSIX path of f
        on error
            return ""
        end try
    end tell
    """
    var error: NSDictionary?
    if let result = NSAppleScript(source: script)?.executeAndReturnError(&error) {
        let path = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty && path != "CANCELED" {
            return path
        }
    }
    return nil
}

func importWebP(sourcePath: String, widgetDir: String, instanceId: String) -> String? {
    let fileManager = FileManager.default
    let stickersDir = (widgetDir as NSString).appendingPathComponent("stickers")
    try? fileManager.createDirectory(atPath: stickersDir, withIntermediateDirectories: true)

    let originalName = URL(fileURLWithPath: sourcePath).lastPathComponent
    let cleanName = originalName.replacingOccurrences(of: " ", with: "_")
    let destPath = (stickersDir as NSString).appendingPathComponent(cleanName)

    let repoStickersDir = "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers"
    let repoDestPath = (repoStickersDir as NSString).appendingPathComponent(cleanName)

    do {
        if fileManager.fileExists(atPath: destPath) {
            try? fileManager.removeItem(atPath: destPath)
        }
        try fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: URL(fileURLWithPath: destPath))

        if fileManager.fileExists(atPath: repoStickersDir) {
            if fileManager.fileExists(atPath: repoDestPath) {
                try? fileManager.removeItem(atPath: repoDestPath)
            }
            try? fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: URL(fileURLWithPath: repoDestPath))
        }

        // Automatically generate sprite sheet and meta JSON for instant frame-freezing
        let scriptPath = (widgetDir as NSString).appendingPathComponent("sheet_generator.py")
        if fileManager.fileExists(atPath: scriptPath) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [scriptPath, destPath, stickersDir]
            try? task.run()
            task.waitUntilExit()
        }
        if fileManager.fileExists(atPath: repoStickersDir) {
            let repoScript = ((repoStickersDir as NSString).deletingLastPathComponent as NSString).appendingPathComponent("sheet_generator.py")
            if fileManager.fileExists(atPath: repoScript) {
                let repoTask = Process()
                repoTask.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                repoTask.arguments = [repoScript, repoDestPath, repoStickersDir]
                try? repoTask.run()
                repoTask.waitUntilExit()
            }
        }

        let relPath = "sticker.widget/stickers/\(cleanName)"
        return "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(relPath)\",\"name\":\"\(cleanName)\"}"
    } catch {
        return nil
    }
}

func pickAndImport(widgetDir: String, instanceId: String) -> String? {
    guard let src = chooseWebPFile() else { return nil }
    return importWebP(sourcePath: src, widgetDir: widgetDir, instanceId: instanceId)
}

func getLocalStickers(widgetDir: String) -> [(filename: String, title: String, relPath: String)] {
    let fileManager = FileManager.default
    let stickersDir = (widgetDir as NSString).appendingPathComponent("stickers")
    guard let files = try? fileManager.contentsOfDirectory(atPath: stickersDir) else {
        return []
    }
    return files
        .filter { $0.lowercased().hasSuffix(".webp") && !$0.lowercased().hasSuffix("_sheet.webp") && !$0.hasPrefix(".") }
        .sorted()
        .map { filename in
            let rawTitle = (filename as NSString).deletingPathExtension
            let cleanTitle = rawTitle.replacingOccurrences(of: "_", with: " ")
            let relPath = "sticker.widget/stickers/\(filename)"
            return (filename: filename, title: cleanTitle, relPath: relPath)
        }
}

func removeStickerFiles(stickerRelPath: String, widgetDir: String) {
    let fileManager = FileManager.default
    let filename = URL(fileURLWithPath: stickerRelPath).lastPathComponent
    let baseName = (filename as NSString).deletingPathExtension
    if baseName.isEmpty { return }

    let stickersDir = (widgetDir as NSString).appendingPathComponent("stickers")
    let repoStickersDir = "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers"
    let widgetDirStr = widgetDir
    let repoDirStr = "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget"

    let dirsToCheck = [stickersDir, repoStickersDir, widgetDirStr, repoDirStr]

    for dir in dirsToCheck {
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
        for f in files {
            if f == filename ||
               f == "\(baseName).webp" ||
               f == "\(baseName)_sheet.webp" ||
               f == "\(baseName)_meta.json" {
                let fullPath = (dir as NSString).appendingPathComponent(f)
                try? fileManager.removeItem(atPath: fullPath)
            }
        }
    }
}

func reloadWidget(widgetId: String) {
    let script = "tell application id \"tracesOf.Uebersicht\" to reload widget id \"\(widgetId)\""
    var err: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&err)
    if err != nil {
        let refreshScript = "tell application id \"tracesOf.Uebersicht\" to refresh"
        NSAppleScript(source: refreshScript)?.executeAndReturnError(nil)
    }
}

// MARK: - Sticker Manager UI Components

class DragDroppableView: NSVisualEffectView {
    var onDropFiles: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if let types = pboard.types, types.contains(.fileURL) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        guard let items = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        onDropFiles?(items)
        return true
    }
}

class StickerCardView: NSView {
    let item: StickerItem
    let onSelect: (StickerItem) -> Void
    let onDelete: (StickerItem) -> Void
    var isHovered: Bool = false
    var trackingArea: NSTrackingArea?

    init(item: StickerItem, frame: NSRect, onSelect: @escaping (StickerItem) -> Void, onDelete: @escaping (StickerItem) -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onDelete = onDelete
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        updateColors()
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateColors() {
        layer?.backgroundColor = isHovered ? CGColor(gray: 1.0, alpha: 0.15) : CGColor(gray: 1.0, alpha: 0.07)
        layer?.borderColor = isHovered ? CGColor(gray: 1.0, alpha: 0.32) : CGColor(gray: 1.0, alpha: 0.12)
        layer?.borderWidth = 1
    }

    func setupUI() {
        let imgView = NSImageView(frame: NSRect(x: 10, y: 32, width: bounds.width - 20, height: bounds.height - 42))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = item.image
        imgView.unregisterDraggedTypes()
        addSubview(imgView)

        let label = NSTextField(frame: NSRect(x: 6, y: 6, width: bounds.width - 12, height: 18))
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.stringValue = item.title
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        if item.isInUse {
            let badge = NSTextField(frame: NSRect(x: 6, y: bounds.height - 22, width: 44, height: 15))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.backgroundColor = CGColor(srgbRed: 0.15, green: 0.45, blue: 0.95, alpha: 0.9)
            badge.isBezeled = false
            badge.drawsBackground = false
            badge.isEditable = false
            badge.isSelectable = false
            badge.stringValue = "ACTIVE"
            badge.font = .systemFont(ofSize: 7.5, weight: .bold)
            badge.textColor = .white
            badge.alignment = .center
            addSubview(badge)
        }

        let delBtn = NSButton(frame: NSRect(x: bounds.width - 24, y: bounds.height - 24, width: 18, height: 18))
        delBtn.isBordered = false
        if let trashImg = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
            delBtn.image = trashImg
            delBtn.imageScaling = .scaleProportionallyDown
            delBtn.contentTintColor = NSColor(white: 0.65, alpha: 0.8)
        } else {
            delBtn.title = "×"
            delBtn.font = .systemFont(ofSize: 14, weight: .bold)
        }
        delBtn.target = self
        delBtn.action = #selector(deleteClicked)
        addSubview(delBtn)
    }

    @objc func deleteClicked() {
        onDelete(item)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateColors()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x > bounds.width - 28 && loc.y > bounds.height - 28 {
            return
        }
        onSelect(item)
    }
}

class StickerManagerController: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    let widgetDir: String
    let instanceId: String
    let currentSticker: String?

    var panel: NSPanel!
    var visualEffect: DragDroppableView!
    var searchField: NSSearchField!
    var scrollView: NSScrollView!
    var gridView: NSView!
    var statusLabel: NSTextField!

    var allItems: [StickerItem] = []
    var filteredItems: [StickerItem] = []
    var outputAction: String?
    var deletedActiveSticker: Bool = false

    init(widgetDir: String, instanceId: String, currentSticker: String?) {
        self.widgetDir = widgetDir
        self.instanceId = instanceId
        self.currentSticker = currentSticker
        super.init()
        setupUI()
        loadStickers()
    }

    func setupUI() {
        let w: CGFloat = 580
        let h: CGFloat = 460
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 440, height: 320)
        panel.maxSize = NSSize(width: 840, height: 640)
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        visualEffect = DragDroppableView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        panel.contentView = visualEffect

        visualEffect.onDropFiles = { [weak self] urls in
            guard let self = self else { return }
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ext == "webp" || ext == "gif" {
                    _ = importWebP(sourcePath: url.path, widgetDir: self.widgetDir, instanceId: self.instanceId)
                }
            }
            self.loadStickers()
        }

        // Header view
        let headerView = NSView(frame: NSRect(x: 0, y: h - 54, width: w, height: 54))
        headerView.autoresizingMask = [.width, .minYMargin]

        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 16, width: 130, height: 22))
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.stringValue = "Sticker Library"
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)

        searchField = NSSearchField(frame: NSRect(x: 160, y: 13, width: 240, height: 26))
        searchField.placeholderString = "Search stickers…"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        headerView.addSubview(searchField)

        let addBtn = NSButton(frame: NSRect(x: w - 150, y: 13, width: 130, height: 26))
        addBtn.autoresizingMask = [.minXMargin]
        addBtn.bezelStyle = .rounded
        addBtn.title = "+ Add Sticker…"
        addBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
        addBtn.target = self
        addBtn.action = #selector(addStickerClicked)
        headerView.addSubview(addBtn)

        let headerBorder = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 1))
        headerBorder.autoresizingMask = [.width]
        headerBorder.wantsLayer = true
        headerBorder.layer?.backgroundColor = CGColor(gray: 1.0, alpha: 0.12)
        headerView.addSubview(headerBorder)

        visualEffect.addSubview(headerView)

        // Scroll view & Grid
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 36, width: w, height: h - 54 - 36))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        gridView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 400))
        scrollView.documentView = gridView
        visualEffect.addSubview(scrollView)

        // Status bar
        let footerBorder = NSView(frame: NSRect(x: 0, y: 35, width: w, height: 1))
        footerBorder.autoresizingMask = [.width, .maxYMargin]
        footerBorder.wantsLayer = true
        footerBorder.layer?.backgroundColor = CGColor(gray: 1.0, alpha: 0.10)
        visualEffect.addSubview(footerBorder)

        statusLabel = NSTextField(frame: NSRect(x: 20, y: 8, width: w - 40, height: 18))
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(white: 0.65, alpha: 0.9)
        visualEffect.addSubview(statusLabel)
    }

    func loadStickers() {
        let locals = getLocalStickers(widgetDir: widgetDir)
        let stickersDir = (widgetDir as NSString).appendingPathComponent("stickers")

        allItems = locals.map { item in
            let fullPath = (stickersDir as NSString).appendingPathComponent(item.filename)
            let img = NSImage(contentsOfFile: fullPath)
            let inUse = (currentSticker != nil && currentSticker!.hasSuffix(item.filename))
            return StickerItem(
                filename: item.filename,
                title: item.title,
                relPath: item.relPath,
                image: img,
                isInUse: inUse
            )
        }

        filterAndLayout()
    }

    @objc func searchChanged() {
        filterAndLayout()
    }

    func filterAndLayout() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { $0.title.lowercased().contains(query) }
        }

        statusLabel.stringValue = "\(allItems.count) stickers in library • Drag & drop WebP files here"
        layoutGrid()
    }

    func layoutGrid() {
        gridView.subviews.forEach { $0.removeFromSuperview() }

        if filteredItems.isEmpty {
            let msgLabel = NSTextField(frame: NSRect(x: 20, y: scrollView.contentSize.height / 2 - 20, width: scrollView.contentSize.width - 40, height: 40))
            msgLabel.isBezeled = false
            msgLabel.drawsBackground = false
            msgLabel.isEditable = false
            msgLabel.isSelectable = false
            msgLabel.alignment = .center
            msgLabel.textColor = NSColor(white: 0.6, alpha: 0.9)
            if allItems.isEmpty {
                msgLabel.stringValue = "No stickers yet.\nClick '+ Add Sticker…' or drag and drop WebP files here."
            } else {
                msgLabel.stringValue = "No stickers matching '\(searchField.stringValue)'"
            }
            msgLabel.font = .systemFont(ofSize: 13)
            gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
            gridView.addSubview(msgLabel)
            return
        }

        let cardW: CGFloat = 125
        let cardH: CGFloat = 135
        let pad: CGFloat = 16
        let gap: CGFloat = 14

        let availableW = max(100, scrollView.contentSize.width - pad * 2)
        let cols = max(1, Int((availableW + gap) / (cardW + gap)))
        let rows = Int(ceil(Double(filteredItems.count) / Double(cols)))
        let totalH = max(scrollView.contentSize.height, CGFloat(rows) * (cardH + gap) + pad * 2)

        gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: totalH)

        for (index, item) in filteredItems.enumerated() {
            let r = index / cols
            let c = index % cols
            let x = pad + CGFloat(c) * (cardW + gap)
            let y = totalH - pad - CGFloat(r + 1) * cardH - CGFloat(r) * gap

            let card = StickerCardView(
                item: item,
                frame: NSRect(x: x, y: y, width: cardW, height: cardH),
                onSelect: { [weak self] selected in
                    self?.selectSticker(selected)
                },
                onDelete: { [weak self] toDelete in
                    self?.confirmDelete(toDelete)
                }
            )
            gridView.addSubview(card)
        }
    }

    func selectSticker(_ item: StickerItem) {
        outputAction = "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(item.relPath)\",\"name\":\"\(item.filename)\"}"
        close()
    }

    func confirmDelete(_ item: StickerItem) {
        let alert = NSAlert()
        alert.messageText = "Delete Sticker?"
        alert.informativeText = "Are you sure you want to permanently delete \"\(item.title)\" from your library? Any widget displaying it will be cleared."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            removeStickerFiles(stickerRelPath: item.relPath, widgetDir: widgetDir)
            if item.isInUse {
                deletedActiveSticker = true
            }
            loadStickers()
        }
    }

    @objc func addStickerClicked() {
        if pickAndImport(widgetDir: widgetDir, instanceId: instanceId) != nil {
            loadStickers()
        }
    }

    func runModal() -> String? {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.run()
        return outputAction
    }

    func close() {
        panel.orderOut(nil)
        if outputAction == nil && deletedActiveSticker {
            outputAction = "{\"action\":\"CLEAR_STICKER\",\"instanceId\":\"\(instanceId)\"}"
        }
        NSApp.stop(nil)
        let dummy = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )
        if let dummy = dummy {
            NSApp.postEvent(dummy, atStart: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    func windowDidResize(_ notification: Notification) {
        layoutGrid()
    }
}

func openStickerManager(widgetDir: String, instanceId: String, currentSticker: String?) -> String? {
    let controller = StickerManagerController(widgetDir: widgetDir, instanceId: instanceId, currentSticker: currentSticker)
    return controller.runModal()
}

// MARK: - Main Execution

var state = MenuState()
if CommandLine.arguments.count > 1 {
    let jsonStr = CommandLine.arguments[1]
    if let data = jsonStr.data(using: .utf8) {
        state = (try? JSONDecoder().decode(MenuState.self, from: data)) ?? MenuState()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MenuDelegate()
let helperPath = CommandLine.arguments[0]
let widgetDir = URL(fileURLWithPath: helperPath).deletingLastPathComponent().path
let widgetFolder = URL(fileURLWithPath: helperPath).deletingLastPathComponent().lastPathComponent
let widgetId = widgetFolder.replacingOccurrences(of: ".", with: "-") + "-index-jsx"

let mode = state.mode ?? "CONTEXT_MENU"
let instanceId = state.instanceId ?? "default"
let localStickers = getLocalStickers(widgetDir: widgetDir)

if mode == "PICK_ONLY" {
    if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
        print(result)
    }
    exit(0)
}

if mode == "MANAGER" {
    if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker) {
        print(result)
    }
    exit(0)
}

if mode == "PLUS_CLICK" {
    // If no local stickers exist yet, directly open Sticker Manager for visual onboarding
    if localStickers.isEmpty {
        if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker) {
            print(result)
        }
        exit(0)
    }

    // Compact popup menu listing "Sticker Library…", local stickers, and "Choose from Finder…"
    let menu = NSMenu(title: "Select Sticker")
    menu.autoenablesItems = false

    let managerItem = NSMenuItem(title: "🖼️ Sticker Library…", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    managerItem.target = delegate
    managerItem.representedObject = "{\"action\":\"OPEN_MANAGER\",\"instanceId\":\"\(instanceId)\"}"
    menu.addItem(managerItem)

    menu.addItem(NSMenuItem.separator())

    for sticker in localStickers {
        let item = NSMenuItem(title: sticker.title, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
        item.target = delegate
        item.representedObject = "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(sticker.relPath)\",\"name\":\"\(sticker.filename)\"}"
        if let cur = state.currentSticker, cur.hasSuffix(sticker.filename) {
            item.state = .on
        }
        menu.addItem(item)
    }

    menu.addItem(NSMenuItem.separator())

    let finderItem = NSMenuItem(title: "Choose from Finder…", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    finderItem.target = delegate
    finderItem.representedObject = "{\"action\":\"TRIGGER_FINDER_PICKER\",\"instanceId\":\"\(instanceId)\"}"
    menu.addItem(finderItem)

    let mouseLoc = NSEvent.mouseLocation
    menu.popUp(positioning: nil, at: mouseLoc, in: nil)

    if let action = delegate.outputAction {
        if action.contains("OPEN_MANAGER") {
            if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker) {
                print(result)
            }
        } else if action.contains("TRIGGER_FINDER_PICKER") {
            if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
                print(result)
            }
        } else {
            print(action)
        }
    }
    exit(0)
}

// CONTEXT_MENU mode
let menu = NSMenu(title: "Sticker Controls")
menu.autoenablesItems = false

let hasSticker = state.currentSticker != nil && !(state.currentSticker?.isEmpty ?? true)

// 1. Sticker Management Section
let managerMenuItem = NSMenuItem(title: "🖼️ Sticker Library…", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
managerMenuItem.target = delegate
managerMenuItem.representedObject = "{\"action\":\"OPEN_MANAGER\",\"instanceId\":\"\(instanceId)\"}"
menu.addItem(managerMenuItem)

if !localStickers.isEmpty {
    let quickSwitchParent = NSMenuItem(title: "⚡ Quick Switch", action: nil, keyEquivalent: "")
    let quickSwitchMenu = NSMenu(title: "Quick Switch")
    quickSwitchMenu.autoenablesItems = false
    for sticker in localStickers {
        let item = NSMenuItem(title: sticker.title, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
        item.target = delegate
        item.representedObject = "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(sticker.relPath)\",\"name\":\"\(sticker.filename)\"}"
        if let cur = state.currentSticker, cur.hasSuffix(sticker.filename) {
            item.state = .on
        }
        quickSwitchMenu.addItem(item)
    }
    quickSwitchParent.submenu = quickSwitchMenu
    menu.addItem(quickSwitchParent)
}

if hasSticker {
    let clearFromWidget = NSMenuItem(title: "⭕ Clear from Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    clearFromWidget.target = delegate
    clearFromWidget.representedObject = "{\"action\":\"CLEAR_FROM_WIDGET\",\"instanceId\":\"\(instanceId)\"}"
    menu.addItem(clearFromWidget)
}

// 2. Sticker Display Controls (if has sticker)
if hasSticker {
    menu.addItem(NSMenuItem.separator())

    // Size Submenu
    let currentScale = state.scale ?? 1.0
    let sizeParent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
    let sizeMenu = NSMenu(title: "Size")
    sizeMenu.autoenablesItems = false
    let sizeOptions: [(String, Double)] = [
        ("50%", 0.5),
        ("75%", 0.75),
        ("100%", 1.0),
        ("125%", 1.25),
        ("150%", 1.5)
    ]
    for (label, val) in sizeOptions {
        let item = NSMenuItem(title: label, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
        item.target = delegate
        item.representedObject = "{\"action\":\"SET_SCALE\",\"instanceId\":\"\(instanceId)\",\"scale\":\(val)}"
        if abs(currentScale - val) < 0.01 {
            item.state = .on
        }
        sizeMenu.addItem(item)
    }
    sizeParent.submenu = sizeMenu
    menu.addItem(sizeParent)

    // Direction Submenu
    let isFlipped = state.flipped ?? false
    let dirParent = NSMenuItem(title: "Facing Direction", action: nil, keyEquivalent: "")
    let dirMenu = NSMenu(title: "Facing Direction")
    dirMenu.autoenablesItems = false
    let leftItem = NSMenuItem(title: "◀ Face Left", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    leftItem.target = delegate
    leftItem.representedObject = "{\"action\":\"SET_FLIP\",\"instanceId\":\"\(instanceId)\",\"flipped\":true}"
    if isFlipped { leftItem.state = .on }
    dirMenu.addItem(leftItem)

    let rightItem = NSMenuItem(title: "Face Right ▶", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    rightItem.target = delegate
    rightItem.representedObject = "{\"action\":\"SET_FLIP\",\"instanceId\":\"\(instanceId)\",\"flipped\":false}"
    if !isFlipped { rightItem.state = .on }
    dirMenu.addItem(rightItem)
    dirParent.submenu = dirMenu
    menu.addItem(dirParent)

    // Opacity Submenu
    let currentOpacity = state.opacity ?? 1.0
    let opParent = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
    let opMenu = NSMenu(title: "Opacity")
    opMenu.autoenablesItems = false
    let opacityOptions: [(String, Double)] = [
        ("100%", 1.0),
        ("80%", 0.8),
        ("60%", 0.6),
        ("40%", 0.4)
    ]
    for (label, val) in opacityOptions {
        let item = NSMenuItem(title: label, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
        item.target = delegate
        item.representedObject = "{\"action\":\"SET_OPACITY\",\"opacity\":\(val)}"
        if abs(currentOpacity - val) < 0.01 {
            item.state = .on
        }
        opMenu.addItem(item)
    }
    opParent.submenu = opMenu
    menu.addItem(opParent)

    menu.addItem(NSMenuItem.separator())

    // Animation Pause / Resume
    let isPaused = state.isPaused ?? false
    let animTitle = isPaused ? "▶ Resume Animation" : "⏸ Pause Animation"
    let animItem = NSMenuItem(title: animTitle, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    animItem.target = delegate
    animItem.representedObject = "{\"action\":\"TOGGLE_PAUSE\",\"instanceId\":\"\(instanceId)\"}"
    menu.addItem(animItem)

    // Audio Stream Animation Playback Toggle
    let hasAudioSync = state.audioSync ?? false
    let syncItem = NSMenuItem(title: "🎵 Sync with Audio Stream", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    syncItem.target = delegate
    syncItem.representedObject = "{\"action\":\"TOGGLE_AUDIO_SYNC\",\"instanceId\":\"\(instanceId)\"}"
    if hasAudioSync { syncItem.state = .on }
    menu.addItem(syncItem)
}

menu.addItem(NSMenuItem.separator())

// Order Submenu
let orderParent = NSMenuItem(title: "Order", action: nil, keyEquivalent: "")
let orderMenu = NSMenu(title: "Order")
orderMenu.autoenablesItems = false
let orderOptions: [(String, String)] = [
    ("Bring to Front", "ORDER_FRONT"),
    ("Bring Forward", "ORDER_FORWARD"),
    ("Send Backward", "ORDER_BACKWARD"),
    ("Send to Back", "ORDER_BACK")
]
for (label, act) in orderOptions {
    let item = NSMenuItem(title: label, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = "{\"action\":\"\(act)\"}"
    orderMenu.addItem(item)
}
orderParent.submenu = orderMenu
menu.addItem(orderParent)

if hasSticker {
    let hasShadow = state.shadow ?? true
    let shadowItem = NSMenuItem(title: "Ambient Shadow", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    shadowItem.target = delegate
    shadowItem.representedObject = "{\"action\":\"TOGGLE_SHADOW\"}"
    if hasShadow { shadowItem.state = .on }
    menu.addItem(shadowItem)
}

let hasSnapping = state.enableSnapping ?? true
let snapItem = NSMenuItem(title: "Snap to Edges", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
snapItem.target = delegate
snapItem.representedObject = "{\"action\":\"TOGGLE_SNAPPING\"}"
if hasSnapping { snapItem.state = .on }
menu.addItem(snapItem)

menu.addItem(NSMenuItem.separator())

// Reset Position
let resetItem = NSMenuItem(title: "Reset Position", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
resetItem.target = delegate
resetItem.representedObject = "{\"action\":\"RESET_POSITION\",\"instanceId\":\"\(instanceId)\"}"
menu.addItem(resetItem)

// Reload Widget
let reloadItem = NSMenuItem(title: "Reload Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
reloadItem.target = delegate
reloadItem.representedObject = "{\"action\":\"RELOAD_WIDGET\",\"widgetId\":\"\(widgetId)\"}"
menu.addItem(reloadItem)

// Duplicate Widget
let dupItem = NSMenuItem(title: "Duplicate Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
dupItem.target = delegate
dupItem.representedObject = "{\"action\":\"DUPLICATE_WIDGET\",\"instanceId\":\"\(instanceId)\"}"
menu.addItem(dupItem)

// Remove Widget
let removeItem = NSMenuItem(title: "Remove Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
removeItem.target = delegate
removeItem.representedObject = "{\"action\":\"REMOVE_WIDGET\",\"instanceId\":\"\(instanceId)\",\"widgetId\":\"\(widgetId)\"}"
menu.addItem(removeItem)

// Pop up native menu above all windows at cursor location
let mouseLoc = NSEvent.mouseLocation
menu.popUp(positioning: nil, at: mouseLoc, in: nil)

if let action = delegate.outputAction {
    if action.contains("OPEN_MANAGER") {
        if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker) {
            print(result)
        }
    } else if action.contains("TRIGGER_FINDER_PICKER") {
        if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
            print(result)
        }
    } else {
        if let data = action.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let act = json["action"] as? String {
            if act == "CLEAR_STICKER" {
                if let st = json["sticker"] as? String {
                    removeStickerFiles(stickerRelPath: st, widgetDir: widgetDir)
                }
            } else if act == "RELOAD_WIDGET" {
                reloadWidget(widgetId: widgetId)
            }
        }
        print(action)
    }
}
