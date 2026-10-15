import AppKit
import Foundation

struct MenuState: Codable {
    var scale: Double?
    var flipped: Bool?
    var isPaused: Bool?
    var opacity: Double?
    var shadow: Bool?
    var snapping: Bool?
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
let currentOpacity = state.opacity ?? 1.0
let hasShadow = state.shadow ?? true
let hasSnapping = state.snapping ?? true

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MenuDelegate()
let menu = NSMenu(title: "Spider-Man Controls")
menu.autoenablesItems = false

// Header Item
let header = NSMenuItem(title: "🕷️ Spider-Man Sticker", action: nil, keyEquivalent: "")
header.isEnabled = false
menu.addItem(header)
menu.addItem(NSMenuItem.separator())

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

menu.addItem(NSMenuItem.separator())

// Reset Position
let resetItem = NSMenuItem(title: "Reset Position", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
resetItem.target = delegate
resetItem.representedObject = "{\"action\":\"RESET_POSITION\"}"
menu.addItem(resetItem)

// Pop up native menu above all windows at cursor location
let mouseLoc = NSEvent.mouseLocation
menu.popUp(positioning: nil, at: mouseLoc, in: nil)

if let action = delegate.outputAction {
    print(action)
}
