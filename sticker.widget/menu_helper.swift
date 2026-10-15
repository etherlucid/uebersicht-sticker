import AppKit
import Foundation

struct MenuState: Codable {
    var scale: Double?
    var flipped: Bool?
    var isPaused: Bool?
    var audioSync: Bool?
    var opacity: Double?
    var shadow: Bool?
    var snapping: Bool?
    var x: Int?
    var y: Int?
}

class MenuDelegate: NSObject {
    var outputAction: String?

    @objc func handleItem(_ sender: NSMenuItem) {
        outputAction = sender.representedObject as? String
    }
}

var state = MenuState()
if CommandLine.arguments.count > 1 {
    let jsonStr = CommandLine.arguments[1]
    if let data = jsonStr.data(using: .utf8) {
        state = (try? JSONDecoder().decode(MenuState.self, from: data)) ?? MenuState()
    }
}

let currentScale = state.scale ?? 1.0
let isFlipped = state.flipped ?? false
let isPaused = state.isPaused ?? false
let hasAudioSync = state.audioSync ?? false
let currentOpacity = state.opacity ?? 1.0
let hasShadow = state.shadow ?? true
let hasSnapping = state.snapping ?? true

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MenuDelegate()
let menu = NSMenu(title: "Spider-Man Controls")
menu.autoenablesItems = false

// Size Submenu
let sizeParent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
let sizeMenu = NSMenu(title: "Size")
sizeMenu.autoenablesItems = false
let sizeOptions: [(String, Double)] = [
    ("50% (Mini)", 0.5),
    ("75% (Compact)", 0.75),
    ("100% (Normal)", 1.0),
    ("125% (Large)", 1.25),
    ("150% (Giant)", 1.5)
]
for (label, val) in sizeOptions {
    let item = NSMenuItem(title: label, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = "{\"action\":\"SET_SCALE\",\"scale\":\(val)}"
    if abs(currentScale - val) < 0.01 {
        item.state = .on
    }
    sizeMenu.addItem(item)
}
sizeParent.submenu = sizeMenu
menu.addItem(sizeParent)

// Direction Submenu
let dirParent = NSMenuItem(title: "Facing Direction", action: nil, keyEquivalent: "")
let dirMenu = NSMenu(title: "Facing Direction")
dirMenu.autoenablesItems = false
let leftItem = NSMenuItem(title: "◀ Face Left", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
leftItem.target = delegate
leftItem.representedObject = "{\"action\":\"SET_FLIP\",\"flipped\":true}"
if isFlipped { leftItem.state = .on }
dirMenu.addItem(leftItem)

let rightItem = NSMenuItem(title: "Face Right ▶", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
rightItem.target = delegate
rightItem.representedObject = "{\"action\":\"SET_FLIP\",\"flipped\":false}"
if !isFlipped { rightItem.state = .on }
dirMenu.addItem(rightItem)
dirParent.submenu = dirMenu
menu.addItem(dirParent)

// Animation Toggle
let animTitle = isPaused ? "▶ Resume Animation" : "⏸ Pause Animation"
let animItem = NSMenuItem(title: animTitle, action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
animItem.target = delegate
animItem.representedObject = "{\"action\":\"TOGGLE_PAUSE\"}"
menu.addItem(animItem)

// Audio Sync Toggle
let syncItem = NSMenuItem(title: "🎵 Sync with System Audio", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
syncItem.target = delegate
syncItem.representedObject = "{\"action\":\"TOGGLE_AUDIO_SYNC\"}"
if hasAudioSync { syncItem.state = .on }
menu.addItem(syncItem)

// Opacity Submenu
let opParent = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
let opMenu = NSMenu(title: "Opacity")
opMenu.autoenablesItems = false
let opacityOptions: [(String, Double)] = [
    ("100% (Solid)", 1.0),
    ("80%", 0.8),
    ("60%", 0.6),
    ("40% (Ghost)", 0.4)
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

// Toggles
let shadowItem = NSMenuItem(title: "Ambient Shadow", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
shadowItem.target = delegate
shadowItem.representedObject = "{\"action\":\"TOGGLE_SHADOW\"}"
if hasShadow { shadowItem.state = .on }
menu.addItem(shadowItem)

let snapItem = NSMenuItem(title: "Edge Snapping", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
snapItem.target = delegate
snapItem.representedObject = "{\"action\":\"TOGGLE_SNAPPING\"}"
if hasSnapping { snapItem.state = .on }
menu.addItem(snapItem)

let helperPath = CommandLine.arguments[0]
let widgetDir = URL(fileURLWithPath: helperPath).deletingLastPathComponent().path
let widgetFolder = URL(fileURLWithPath: helperPath).deletingLastPathComponent().lastPathComponent
let widgetId = widgetFolder.replacingOccurrences(of: ".", with: "-") + "-index-jsx"

func duplicateWidget(widgetDir: String, currentX: Int, currentY: Int) -> String? {
    let fileManager = FileManager.default
    let parentDir = (widgetDir as NSString).deletingLastPathComponent
    let folderName = (widgetDir as NSString).lastPathComponent

    let rawName = folderName.replacingOccurrences(of: ".widget", with: "")
    let regex = try? NSRegularExpression(pattern: "^(.*?)(?:-\\d+)?$")
    var baseName = rawName
    if let match = regex?.firstMatch(in: rawName, range: NSRange(rawName.startIndex..., in: rawName)),
       let r = Range(match.range(at: 1), in: rawName) {
        baseName = String(rawName[r])
    }

    var n = 2
    var targetDir = ""
    var targetName = ""
    while true {
        targetName = "\(baseName)-\(n).widget"
        targetDir = (parentDir as NSString).appendingPathComponent(targetName)
        if !fileManager.fileExists(atPath: targetDir) {
            break
        }
        n += 1
    }

    do {
        try fileManager.copyItem(atPath: widgetDir, toPath: targetDir)

        let indexPath = (targetDir as NSString).appendingPathComponent("index.jsx")
        if let data = fileManager.contents(atPath: indexPath),
           var content = String(data: data, encoding: .utf8) {

            if let keyRegex = try? NSRegularExpression(pattern: "(STORAGE_\\w+_KEY|POS_KEY|SIZE_KEY|STORAGE_KEY)(\\s*=\\s*['\"])([^'\"]+)(['\"])") {
                content = keyRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "$1$2$3_\(n)$4")
            }

            if let defXRegex = try? NSRegularExpression(pattern: "(defaultX\\s*=\\s*)(\\d+)") {
                content = defXRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "$1\(currentX + 30)")
            }

            if let defYRegex = try? NSRegularExpression(pattern: "(defaultY\\s*=\\s*)(\\d+)") {
                content = defYRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "$1\(currentY + 30)")
            }

            try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }

        let script = "tell application id \"tracesOf.Uebersicht\" to refresh"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
        return targetName
    } catch {
        return nil
    }
}

func removeWidget(widgetDir: String, widgetId: String, widgetFolder: String) {
    let isDuplicate = widgetFolder.range(of: "-(\\d+)\\.widget$", options: .regularExpression) != nil ||
                      widgetFolder.contains("copy")
    if isDuplicate {
        let script = "tell application \"Finder\" to delete POSIX file \"\(widgetDir)\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    } else {
        let script = "tell application id \"tracesOf.Uebersicht\" to set hidden of widget id \"\(widgetId)\" to true"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
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

menu.addItem(NSMenuItem.separator())

// Reset Position
let resetItem = NSMenuItem(title: "Reset Position", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
resetItem.target = delegate
resetItem.representedObject = "{\"action\":\"RESET_POSITION\"}"
menu.addItem(resetItem)

// Reload Widget
let reloadItem = NSMenuItem(title: "Reload Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
reloadItem.target = delegate
reloadItem.representedObject = "{\"action\":\"RELOAD_WIDGET\",\"widgetId\":\"\(widgetId)\",\"widgetDir\":\"\(widgetDir)\",\"widgetFolder\":\"\(widgetFolder)\"}"
menu.addItem(reloadItem)

// Duplicate Widget
let dupItem = NSMenuItem(title: "Duplicate Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
dupItem.target = delegate
dupItem.representedObject = "{\"action\":\"DUPLICATE_WIDGET\",\"widgetId\":\"\(widgetId)\",\"widgetDir\":\"\(widgetDir)\",\"widgetFolder\":\"\(widgetFolder)\"}"
menu.addItem(dupItem)

// Remove Widget
let removeItem = NSMenuItem(title: "Remove Widget", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
removeItem.target = delegate
removeItem.representedObject = "{\"action\":\"REMOVE_WIDGET\",\"widgetId\":\"\(widgetId)\",\"widgetDir\":\"\(widgetDir)\",\"widgetFolder\":\"\(widgetFolder)\"}"
menu.addItem(removeItem)

// Pop up native menu above all windows at cursor location
let mouseLoc = NSEvent.mouseLocation
menu.popUp(positioning: nil, at: mouseLoc, in: nil)

if let action = delegate.outputAction {
    print(action)
    if let data = action.data(using: .utf8),
       let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let act = json["action"] as? String {
        if act == "RELOAD_WIDGET" {
            reloadWidget(widgetId: widgetId)
        } else if act == "DUPLICATE_WIDGET" {
            _ = duplicateWidget(widgetDir: widgetDir, currentX: state.x ?? 100, currentY: state.y ?? 100)
        } else if act == "REMOVE_WIDGET" {
            removeWidget(widgetDir: widgetDir, widgetId: widgetId, widgetFolder: widgetFolder)
        }
    }
}
