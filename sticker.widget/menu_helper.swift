import AppKit
import Foundation

struct MenuState: Codable {
    var mode: String?              // "PLUS_CLICK" or "CONTEXT_MENU" or "PICK_ONLY"
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

if mode == "PLUS_CLICK" {
    // If no local stickers exist yet, directly launch Finder picker!
    if localStickers.isEmpty {
        if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
            print(result)
        }
        exit(0)
    }

    // Otherwise, show popup menu listing local stickers first, then "Choose from Finder..."
    let menu = NSMenu(title: "Select Sticker")
    menu.autoenablesItems = false

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

    if !localStickers.isEmpty {
        let deleteParent = NSMenuItem(title: "Delete Sticker", action: nil, keyEquivalent: "")
        let deleteMenu = NSMenu(title: "Delete Sticker")
        deleteMenu.autoenablesItems = false
        for sticker in localStickers {
            let item = NSMenuItem(title: sticker.title, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
            item.target = delegate
            item.representedObject = "{\"action\":\"CLEAR_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(sticker.relPath)\"}"
            deleteMenu.addItem(item)
        }
        deleteParent.submenu = deleteMenu
        menu.addItem(deleteParent)
    }

    let mouseLoc = NSEvent.mouseLocation
    menu.popUp(positioning: nil, at: mouseLoc, in: nil)

    if let action = delegate.outputAction {
        if action.contains("TRIGGER_FINDER_PICKER") {
            if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
                print(result)
            }
        } else {
            if let data = action.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let act = json["action"] as? String,
               act == "CLEAR_STICKER" {
                if let st = json["sticker"] as? String {
                    removeStickerFiles(stickerRelPath: st, widgetDir: widgetDir)
                }
            }
            print(action)
        }
    }
    exit(0)
}

// CONTEXT_MENU mode
let menu = NSMenu(title: "Sticker Controls")
menu.autoenablesItems = false

let hasSticker = state.currentSticker != nil && !(state.currentSticker?.isEmpty ?? true)

// Change Sticker / Choose Sticker Submenu
let stickerParentTitle = hasSticker ? "Change Sticker" : "Choose Sticker"
let stickerParent = NSMenuItem(title: stickerParentTitle, action: nil, keyEquivalent: "")
let stickerMenu = NSMenu(title: stickerParentTitle)
stickerMenu.autoenablesItems = false

for sticker in localStickers {
    let item = NSMenuItem(title: sticker.title, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(sticker.relPath)\",\"name\":\"\(sticker.filename)\"}"
    if let cur = state.currentSticker, cur.hasSuffix(sticker.filename) {
        item.state = .on
    }
    stickerMenu.addItem(item)
}

if !localStickers.isEmpty {
    stickerMenu.addItem(NSMenuItem.separator())
}

let chooseFinderItem = NSMenuItem(title: "Choose from Finder…", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
chooseFinderItem.target = delegate
chooseFinderItem.representedObject = "{\"action\":\"TRIGGER_FINDER_PICKER\",\"instanceId\":\"\(instanceId)\"}"
stickerMenu.addItem(chooseFinderItem)

if !localStickers.isEmpty {
    let deleteParent = NSMenuItem(title: "Delete Sticker", action: nil, keyEquivalent: "")
    let deleteMenu = NSMenu(title: "Delete Sticker")
    deleteMenu.autoenablesItems = false
    for sticker in localStickers {
        let item = NSMenuItem(title: sticker.title, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
        item.target = delegate
        item.representedObject = "{\"action\":\"CLEAR_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(sticker.relPath)\"}"
        deleteMenu.addItem(item)
    }
    deleteParent.submenu = deleteMenu
    stickerMenu.addItem(deleteParent)
}

if hasSticker, let curSticker = state.currentSticker {
    stickerMenu.addItem(NSMenuItem.separator())
    let clearItem = NSMenuItem(title: "Remove Sticker", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    clearItem.target = delegate
    clearItem.representedObject = "{\"action\":\"CLEAR_STICKER\",\"instanceId\":\"\(instanceId)\",\"sticker\":\"\(curSticker)\"}"
    stickerMenu.addItem(clearItem)
}

stickerParent.submenu = stickerMenu
menu.addItem(stickerParent)

// If has sticker, show Size, Direction, Opacity
if hasSticker {
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
    if action.contains("TRIGGER_FINDER_PICKER") {
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
