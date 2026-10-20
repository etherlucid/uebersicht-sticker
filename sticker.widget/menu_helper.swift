import AppKit
import Foundation
import CoreImage
import Vision
import ImageIO
import UniformTypeIdentifiers

struct MenuState: Codable {
    var mode: String?              // "PLUS_CLICK" or "CONTEXT_MENU" or "PICK_ONLY" or "MANAGER" or "STUDIO" or "SYNC_DISPLAYS"
    var instanceId: String?
    var currentSticker: String?    // relative path e.g. "sticker.widget/stickers/cat.webp" or nil
    var targetName: String?
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

func getUebersichtIcon() -> NSImage? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "tracesOf.Uebersicht") {
        let resIconPath = url.appendingPathComponent("Contents/Resources/AppIcon.icns").path
        if FileManager.default.fileExists(atPath: resIconPath), let img = NSImage(contentsOfFile: resIconPath) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    let candidates = [
        NSHomeDirectory() + "/Applications/Übersicht.app",
        NSHomeDirectory() + "/Applications/Uebersicht.app",
        "/Applications/Übersicht.app",
        "/Applications/Uebersicht.app"
    ]
    for c in candidates {
        let icns = c + "/Contents/Resources/AppIcon.icns"
        if FileManager.default.fileExists(atPath: icns), let img = NSImage(contentsOfFile: icns) {
            return img
        }
        if FileManager.default.fileExists(atPath: c) {
            return NSWorkspace.shared.icon(forFile: c)
        }
    }
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "tracesOf.Uebersicht").first,
       let icon = app.icon {
        return icon
    }
    return nil
}

func setupDockIcon() {
    if let icon = getUebersichtIcon() {
        NSApplication.shared.applicationIconImage = icon
    }
}

class StickerAppDelegate: NSObject, NSApplicationDelegate {
    var getActiveWindow: (() -> NSWindow?)?
    var onNewWindowRequested: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag, let win = getActiveWindow?() {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        } else {
            if let onNew = onNewWindowRequested {
                onNew()
                return false
            } else if let win = getActiveWindow?() {
                if win.isMiniaturized {
                    win.deminiaturize(nil)
                }
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
            return true
        }
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if let onNew = onNewWindowRequested {
            onNew()
            return true
        }
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if let onNew = onNewWindowRequested {
            onNew()
            return true
        }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Dock Menu")
        let item = NSMenuItem(title: "Open Sticker Library", action: #selector(handleDockMenuOpen), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func handleDockMenuOpen() {
        if let win = getActiveWindow?(), win.isVisible {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let onNew = onNewWindowRequested {
            onNew()
        }
    }
}

let appDelegate = StickerAppDelegate()


func chooseImageFile() -> String? {
    let script = """
    tell application "System Events"
        activate
        try
            set f to choose file of type {"org.webmproject.webp", "webp", "com.compuserve.gif", "gif", "public.png", "png", "public.jpeg", "jpg", "jpeg"} with prompt "Select a Sticker (GIF, WebP, PNG, JPG)"
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

func chooseWebPFile() -> String? {
    return chooseImageFile()
}

func importSticker(sourcePath: String, widgetDir: String, instanceId: String) -> String? {
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
            try fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: URL(fileURLWithPath: repoDestPath))
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

func importWebP(sourcePath: String, widgetDir: String, instanceId: String) -> String? {
    return importSticker(sourcePath: sourcePath, widgetDir: widgetDir, instanceId: instanceId)
}

func pickAndImport(widgetDir: String, instanceId: String) -> String? {
    guard let src = chooseImageFile() else { return nil }
    return importSticker(sourcePath: src, widgetDir: widgetDir, instanceId: instanceId)
}

func getLocalStickers(widgetDir: String) -> [(filename: String, title: String, relPath: String)] {
    let fileManager = FileManager.default
    let stickersDir = (widgetDir as NSString).appendingPathComponent("stickers")
    guard let files = try? fileManager.contentsOfDirectory(atPath: stickersDir) else {
        return []
    }
    let allowedExtensions: Set<String> = ["webp", "gif", "png", "jpg", "jpeg"]
    return files
        .filter { file in
            let lower = file.lowercased()
            if lower.hasPrefix(".") || lower.hasSuffix("_sheet.webp") || lower.hasSuffix("_meta.json") {
                return false
            }
            let ext = (lower as NSString).pathExtension
            return allowedExtensions.contains(ext)
        }
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
            let fBase = (f as NSString).deletingPathExtension
            if f == filename ||
               f == "\(baseName)_sheet.webp" ||
               f == "\(baseName)_meta.json" ||
               fBase == baseName ||
               fBase == "\(baseName)_sheet" {
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

func syncWidgetsToTargetDisplay(targetPattern: String = "ASUS") -> String {
    let screens = NSScreen.screens
    var targetScreen: NSScreen? = nil

    // 1. Search for display name containing targetPattern (e.g. "ASUS")
    for s in screens {
        if s.localizedName.localizedCaseInsensitiveContains(targetPattern) {
            targetScreen = s
            break
        }
    }

    // 2. Check for portrait orientation (height > width, e.g. rotated vertical monitor)
    if targetScreen == nil {
        for s in screens {
            if s.frame.height > s.frame.width {
                targetScreen = s
                break
            }
        }
    }

    // 3. Fallback: non-main screen if multiple screens exist
    if targetScreen == nil && screens.count > 1 {
        targetScreen = screens.first(where: { $0 != NSScreen.main })
    }

    guard let foundScreen = targetScreen else {
        return "{\"status\":\"skipped\",\"reason\":\"Target display '\(targetPattern)' not connected\"}"
    }

    guard let screenNumber = foundScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return "{\"status\":\"error\",\"reason\":\"Unable to obtain NSScreenNumber\"}"
    }

    let settingsPath = ("~/Library/Application Support/tracesOf.Uebersicht/WidgetSettings.json" as NSString).expandingTildeInPath
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
          var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else {
        return "{\"status\":\"error\",\"reason\":\"Unable to read WidgetSettings.json\"}"
    }

    let targetWidgets = [
        "sticker-widget-index-jsx",
        "cava-widget-index-jsx",
        "nowplaying-widget-index-jsx",
        "shell-widget-index-jsx"
    ]

    var needsUpdate = false
    for widgetKey in targetWidgets {
        var currentSetting = json[widgetKey] ?? [
            "showOnAllScreens": false,
            "showOnMainScreen": false,
            "showOnSelectedScreens": true,
            "hidden": false,
            "screens": []
        ]

        let curScreens = (currentSetting["screens"] as? [Int]) ?? []
        let curSelected = (currentSetting["showOnSelectedScreens"] as? Bool) ?? false

        if !curSelected || curScreens != [Int(screenNumber)] {
            currentSetting["showOnAllScreens"] = false
            currentSetting["showOnMainScreen"] = false
            currentSetting["showOnSelectedScreens"] = true
            currentSetting["hidden"] = false
            currentSetting["screens"] = [Int(screenNumber)]
            json[widgetKey] = currentSetting
            needsUpdate = true
        }
    }

    if needsUpdate {
        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: settingsPath))

            let script = "tell application id \"tracesOf.Uebersicht\" to refresh"
            NSAppleScript(source: script)?.executeAndReturnError(nil)

            return "{\"status\":\"success\",\"updated\":true,\"screenName\":\"\(foundScreen.localizedName)\",\"screenId\":\(screenNumber)}"
        }
    }

    return "{\"status\":\"success\",\"updated\":false,\"screenName\":\"\(foundScreen.localizedName)\",\"screenId\":\(screenNumber)}"
}

// MARK: - Background Cutout Studio

enum CutoutMode: Int {
    case original = 0
    case colorKey = 1
    case smartAI = 2
}

class CheckerboardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let squareSize: CGFloat = 12
        let cols = Int(ceil(bounds.width / squareSize))
        let rows = Int(ceil(bounds.height / squareSize))
        let c1 = NSColor(white: 0.12, alpha: 1.0)
        let c2 = NSColor(white: 0.18, alpha: 1.0)
        for r in 0..<rows {
            for c in 0..<cols {
                let rect = NSRect(x: CGFloat(c) * squareSize, y: CGFloat(r) * squareSize, width: squareSize, height: squareSize)
                if rect.intersects(dirtyRect) {
                    ((r + c) % 2 == 0 ? c1 : c2).setFill()
                    rect.fill()
                }
            }
        }
    }
}

func samplePixelColor(cgImage: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
    var pixel = [UInt8](repeating: 0, count: 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let clampedX = max(0, min(cgImage.width - 1, x))
    let clampedY = max(0, min(cgImage.height - 1, y))
    guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cgImage, in: CGRect(x: -clampedX, y: -clampedY, width: cgImage.width, height: cgImage.height))
    return (pixel[0], pixel[1], pixel[2])
}

func robustDetectBackground(cgImage: CGImage) -> (r: UInt8, g: UInt8, b: UInt8) {
    let w = cgImage.width, h = cgImage.height
    guard w > 2 && h > 2 else { return (255, 255, 255) }
    var samples: [(r: UInt8, g: UInt8, b: UInt8)] = []
    let xs = [0, w / 4, w / 2, 3 * w / 4, w - 1]
    for x in xs {
        if let p1 = samplePixelColor(cgImage: cgImage, x: x, y: 0) { samples.append(p1) }
        if let p2 = samplePixelColor(cgImage: cgImage, x: x, y: h - 1) { samples.append(p2) }
    }
    for y in [h / 4, h / 2, 3 * h / 4] {
        if let p1 = samplePixelColor(cgImage: cgImage, x: 0, y: y) { samples.append(p1) }
        if let p2 = samplePixelColor(cgImage: cgImage, x: w - 1, y: y) { samples.append(p2) }
    }
    guard !samples.isEmpty else { return (255, 255, 255) }
    var bestSample = samples[0]
    var bestCount = 0
    let thresh: Float = 40.0
    for candidate in samples {
        var count = 0
        let cr = Float(candidate.r), cg = Float(candidate.g), cb = Float(candidate.b)
        for other in samples {
            let dr = Float(other.r) - cr
            let dg = Float(other.g) - cg
            let db = Float(other.b) - cb
            if sqrt(dr*dr + dg*dg + db*db) <= thresh { count += 1 }
        }
        if count > bestCount {
            bestCount = count
            bestSample = candidate
        }
    }
    return bestSample
}

func autoDetectCorners(cgImage: CGImage) -> (r: UInt8, g: UInt8, b: UInt8) {
    return robustDetectBackground(cgImage: cgImage)
}

func createTransparentImage(width: Int, height: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    return ctx.makeImage()
}

func removeBackgroundColor(
    from cgImage: CGImage,
    targetR: UInt8,
    targetG: UInt8,
    targetB: UInt8,
    tolerance: Float,
    smoothness: Float
) -> CGImage? {
    let w = cgImage.width
    let h = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = w * bytesPerPixel
    var rawData = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
    guard let ctx = CGContext(data: &rawData, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    let maxDist: Float = 441.67295593
    let tolDist = max(0.001, tolerance * maxDist)
    let smoothDist = max(0.001, smoothness * maxDist)
    let tR = Float(targetR), tG = Float(targetG), tB = Float(targetB)
    for idx in stride(from: 0, to: w * h * 4, by: 4) {
        let a = rawData[idx + 3]
        if a == 0 { continue }
        let dr = Float(rawData[idx]) - tR
        let dg = Float(rawData[idx + 1]) - tG
        let db = Float(rawData[idx + 2]) - tB
        let dist = sqrt(dr*dr + dg*dg + db*db)
        if dist < tolDist {
            rawData[idx] = 0; rawData[idx+1] = 0; rawData[idx+2] = 0; rawData[idx+3] = 0
        } else if dist < tolDist + smoothDist {
            let factor = (dist - tolDist) / smoothDist
            rawData[idx] = UInt8(Float(rawData[idx]) * factor)
            rawData[idx+1] = UInt8(Float(rawData[idx+1]) * factor)
            rawData[idx+2] = UInt8(Float(rawData[idx+2]) * factor)
            rawData[idx+3] = UInt8(Float(a) * factor)
        }
    }
    return ctx.makeImage()
}

func removeBackgroundSmartAI(
    from cgImage: CGImage,
    fallbackBgColor: (r: UInt8, g: UInt8, b: UInt8)? = nil,
    tolerance: Float = 0.15,
    smoothness: Float = 0.05
) -> CGImage? {
    if #available(macOS 14.0, *) {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([req])
        if let result = req.results?.first, !result.allInstances.isEmpty,
           let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
            let ciInput = CIImage(cgImage: cgImage)
            let ciMask = CIImage(cvPixelBuffer: maskBuffer)
            let blend = CIFilter(name: "CIBlendWithMask")!
            blend.setValue(ciInput, forKey: kCIInputImageKey)
            blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            blend.setValue(ciMask, forKey: kCIInputMaskImageKey)
            if let out = blend.outputImage {
                let ctx = CIContext(options: nil)
                if let outCG = ctx.createCGImage(out, from: ciInput.extent) {
                    return outCG
                }
            }
        }
    }
    // When the neural net finds no foreground instances (e.g. frame is mostly/all background):
    let bg = fallbackBgColor ?? robustDetectBackground(cgImage: cgImage)
    return removeBackgroundColor(from: cgImage, targetR: bg.r, targetG: bg.g, targetB: bg.b, tolerance: tolerance, smoothness: smoothness)
}

func saveStaticPNG(cgImage: CGImage, destURL: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(destURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, cgImage, nil)
    return CGImageDestinationFinalize(dest)
}

func saveAnimatedGIF(frames: [CGImage], delays: [Double], destURL: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(destURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return false }
    let gifProps = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFLoopCount as String: 0
        ]
    ]
    CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
    for (i, frame) in frames.enumerated() {
        let delay = (i < delays.count) ? max(0.02, delays[i]) : 0.07
        let frameProps = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: delay
            ]
        ]
        CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
    }
    return CGImageDestinationFinalize(dest)
}

func resolveStickerPath(_ rel: String?, widgetDir: String) -> String? {
    guard let rel = rel, !rel.isEmpty else { return nil }
    let filename = URL(fileURLWithPath: rel).lastPathComponent
    let fullWidgetPath = (widgetDir as NSString).appendingPathComponent("stickers/\(filename)")
    if FileManager.default.fileExists(atPath: fullWidgetPath) {
        return fullWidgetPath
    }
    let repoPath = "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/\(filename)"
    if FileManager.default.fileExists(atPath: repoPath) {
        return repoPath
    }
    if FileManager.default.fileExists(atPath: rel) {
        return rel
    }
    return nil
}

class InteractivePreviewView: CheckerboardView {
    var onSampleColor: ((UInt8, UInt8, UInt8) -> Void)?
    var currentCGImage: CGImage?
    let imageView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderColor = CGColor(gray: 1.0, alpha: 0.12)
        layer?.borderWidth = 1

        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        guard let cg = currentCGImage else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let viewW = bounds.width
        let viewH = bounds.height
        let imgW = CGFloat(cg.width)
        let imgH = CGFloat(cg.height)
        guard imgW > 0 && imgH > 0 else { return }

        let scale = min(viewW / imgW, viewH / imgH)
        let displayW = imgW * scale
        let displayH = imgH * scale
        let offsetX = (viewW - displayW) / 2.0
        let offsetY = (viewH - displayH) / 2.0

        let relX = loc.x - offsetX
        let relY = loc.y - offsetY
        if relX >= 0 && relX <= displayW && relY >= 0 && relY <= displayH {
            let px = Int((relX / displayW) * imgW)
            let py = Int((relY / displayH) * imgH)
            if let color = samplePixelColor(cgImage: cg, x: px, y: py) {
                onSampleColor?(color.r, color.g, color.b)
            }
        }
    }
}

class StickerCutoutStudioController: NSObject, NSWindowDelegate {
    let sourcePath: String
    let widgetDir: String
    let instanceId: String

    var window: NSWindow!
    var previewView: InteractivePreviewView!
    var modeSegmented: NSSegmentedControl!
    var colorContainer: NSView!
    var aiContainer: NSView!
    var originalContainer: NSView!

    var swatchView: NSView!
    var hexLabel: NSTextField!
    var toleranceSlider: NSSlider!
    var toleranceLabel: NSTextField!
    var featherSlider: NSSlider!
    var featherLabel: NSTextField!

    var playbackBar: NSView?
    var playBtn: NSButton?
    var frameSlider: NSSlider?
    var frameLabel: NSTextField?

    var saveBtn: NSButton!
    var infoLabel: NSTextField!

    var frames: [CGImage] = []
    var frameDelays: [Double] = []
    var isAnimated: Bool = false
    var currentFrameIndex: Int = 0
    var isPlaying: Bool = false
    var playbackTimer: Timer?

    var cutoutMode: CutoutMode = .original
    var targetColor: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255)
    var tolerance: Float = 0.15
    var smoothness: Float = 0.05

    var isStandalone: Bool = false
    var onComplete: ((String?) -> Void)?
    var outputAction: String?

    init(sourcePath: String, widgetDir: String, instanceId: String) {
        self.sourcePath = sourcePath
        self.widgetDir = widgetDir
        self.instanceId = instanceId
        super.init()
        loadSource()
        setupUI()
        updatePreview()
    }

    func loadSource() {
        let url = URL(fileURLWithPath: sourcePath)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) {
                frames.append(cg)
                var delay = 0.07
                if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any],
                   let gifDict = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, unclamped > 0.01 {
                        delay = unclamped
                    } else if let clamped = gifDict[kCGImagePropertyGIFDelayTime as String] as? Double, clamped > 0.01 {
                        delay = clamped
                    }
                }
                frameDelays.append(delay)
            }
        }
        isAnimated = (frames.count > 1)
        if let first = frames.first {
            targetColor = autoDetectCorners(cgImage: first)
        }
    }

    func setupUI() {
        let w: CGFloat = 820
        let h: CGFloat = 580

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 500)
        window.title = "Background Cutout Studio"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        // Top Header (Height 48)
        let headerH: CGFloat = 48
        let headerView = NSView(frame: NSRect(x: 0, y: h - headerH, width: w, height: headerH))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)

        let titleLabel = NSTextField(frame: NSRect(x: 18, y: 14, width: 220, height: 20))
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.stringValue = "✂️ Cutout Studio"
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)

        let filename = URL(fileURLWithPath: sourcePath).lastPathComponent
        let firstW = frames.first?.width ?? 0
        let firstH = frames.first?.height ?? 0
        let infoStr = "\(filename) • \(firstW) × \(firstH) px" + (isAnimated ? " • Animated (\(frames.count) frames)" : " • Static")

        infoLabel = NSTextField(frame: NSRect(x: 230, y: 15, width: w - 246, height: 18))
        infoLabel.autoresizingMask = [.width]
        infoLabel.isBezeled = false
        infoLabel.drawsBackground = false
        infoLabel.isEditable = false
        infoLabel.isSelectable = false
        infoLabel.stringValue = infoStr
        infoLabel.font = .systemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = NSColor(white: 0.65, alpha: 0.9)
        headerView.addSubview(infoLabel)

        let headerBorder = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 1))
        headerBorder.autoresizingMask = [.width]
        headerBorder.wantsLayer = true
        headerBorder.layer?.backgroundColor = CGColor(gray: 1.0, alpha: 0.08)
        headerView.addSubview(headerBorder)
        root.addSubview(headerView)

        // Right Sidebar (Width 270)
        let sideW: CGFloat = 270
        let sideMargin: CGFloat = 16
        let sideH = h - headerH - sideMargin * 2
        let sideView = NSView(frame: NSRect(x: w - sideW - sideMargin, y: sideMargin, width: sideW, height: sideH))
        sideView.autoresizingMask = [.minXMargin, .height]
        sideView.wantsLayer = true
        sideView.layer?.cornerRadius = 10
        sideView.layer?.backgroundColor = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
        sideView.layer?.borderColor = CGColor(gray: 1.0, alpha: 0.08)
        sideView.layer?.borderWidth = 1
        root.addSubview(sideView)

        // Mode Segmented Control
        let modeLabel = NSTextField(frame: NSRect(x: 16, y: sideH - 34, width: sideW - 32, height: 16))
        modeLabel.autoresizingMask = [.minYMargin]
        modeLabel.isBezeled = false
        modeLabel.drawsBackground = false
        modeLabel.isEditable = false
        modeLabel.isSelectable = false
        modeLabel.stringValue = "CUTOUT MODE"
        modeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        modeLabel.textColor = NSColor(white: 0.5, alpha: 0.9)
        sideView.addSubview(modeLabel)

        modeSegmented = NSSegmentedControl(labels: ["⭕ Original", "🎯 Color Key", "🪄 Smart AI"], trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeSegmented.frame = NSRect(x: 14, y: sideH - 68, width: sideW - 28, height: 26)
        modeSegmented.autoresizingMask = [.minYMargin]
        modeSegmented.selectedSegment = CutoutMode.original.rawValue
        sideView.addSubview(modeSegmented)

        // Color Key Container View
        let containerH = sideH - 74 - 58
        colorContainer = NSView(frame: NSRect(x: 0, y: 58, width: sideW, height: containerH))
        colorContainer.autoresizingMask = [.minYMargin, .height]
        colorContainer.isHidden = true
        sideView.addSubview(colorContainer)

        let targetColorTitle = NSTextField(frame: NSRect(x: 16, y: containerH - 26, width: sideW - 32, height: 16))
        targetColorTitle.isBezeled = false
        targetColorTitle.drawsBackground = false
        targetColorTitle.isEditable = false
        targetColorTitle.isSelectable = false
        targetColorTitle.stringValue = "KEY BACKGROUND COLOR"
        targetColorTitle.font = .systemFont(ofSize: 10, weight: .bold)
        targetColorTitle.textColor = NSColor(white: 0.5, alpha: 0.9)
        colorContainer.addSubview(targetColorTitle)

        // Swatch & Hex row
        swatchView = NSView(frame: NSRect(x: 16, y: containerH - 68, width: 36, height: 36))
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 6
        swatchView.layer?.borderWidth = 1.5
        swatchView.layer?.borderColor = CGColor(gray: 1.0, alpha: 0.25)
        colorContainer.addSubview(swatchView)

        hexLabel = NSTextField(frame: NSRect(x: 60, y: containerH - 68, width: 95, height: 36))
        hexLabel.isBezeled = false
        hexLabel.drawsBackground = false
        hexLabel.isEditable = false
        hexLabel.isSelectable = false
        hexLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hexLabel.textColor = .white
        colorContainer.addSubview(hexLabel)

        let autoCornersBtn = NSButton(frame: NSRect(x: sideW - 106, y: containerH - 64, width: 92, height: 28))
        autoCornersBtn.bezelStyle = .rounded
        autoCornersBtn.title = "Corners"
        autoCornersBtn.font = .systemFont(ofSize: 11, weight: .medium)
        autoCornersBtn.target = self
        autoCornersBtn.action = #selector(autoCornersClicked)
        colorContainer.addSubview(autoCornersBtn)

        let hintLabel = NSTextField(frame: NSRect(x: 16, y: containerH - 100, width: sideW - 32, height: 26))
        hintLabel.isBezeled = false
        hintLabel.drawsBackground = false
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        hintLabel.stringValue = "💡 Click anywhere on the preview to sample that pixel color."
        hintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = NSColor(white: 0.55, alpha: 0.9)
        colorContainer.addSubview(hintLabel)

        // Tolerance Slider
        let tolY = containerH - 146
        toleranceLabel = NSTextField(frame: NSRect(x: 16, y: tolY + 20, width: sideW - 32, height: 16))
        toleranceLabel.isBezeled = false
        toleranceLabel.drawsBackground = false
        toleranceLabel.isEditable = false
        toleranceLabel.isSelectable = false
        toleranceLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        toleranceLabel.textColor = .white
        colorContainer.addSubview(toleranceLabel)

        toleranceSlider = NSSlider(value: Double(tolerance * 100), minValue: 0, maxValue: 100, target: self, action: #selector(toleranceChanged))
        toleranceSlider.frame = NSRect(x: 14, y: tolY - 4, width: sideW - 28, height: 22)
        colorContainer.addSubview(toleranceSlider)

        // Smoothness Slider
        let smoothY = containerH - 208
        featherLabel = NSTextField(frame: NSRect(x: 16, y: smoothY + 20, width: sideW - 32, height: 16))
        featherLabel.isBezeled = false
        featherLabel.drawsBackground = false
        featherLabel.isEditable = false
        featherLabel.isSelectable = false
        featherLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        featherLabel.textColor = .white
        colorContainer.addSubview(featherLabel)

        featherSlider = NSSlider(value: Double(smoothness * 100), minValue: 0, maxValue: 30, target: self, action: #selector(featherChanged))
        featherSlider.frame = NSRect(x: 14, y: smoothY - 4, width: sideW - 28, height: 22)
        colorContainer.addSubview(featherSlider)

        updateColorLabels()

        // Smart AI Container View
        aiContainer = NSView(frame: NSRect(x: 0, y: 58, width: sideW, height: containerH))
        aiContainer.autoresizingMask = [.minYMargin, .height]
        aiContainer.isHidden = true
        sideView.addSubview(aiContainer)

        let aiCard = NSView(frame: NSRect(x: 14, y: containerH - 140, width: sideW - 28, height: 120))
        aiCard.wantsLayer = true
        aiCard.layer?.cornerRadius = 8
        aiCard.layer?.backgroundColor = CGColor(gray: 0.18, alpha: 0.6)
        aiContainer.addSubview(aiCard)

        let aiTitle = NSTextField(frame: NSRect(x: 12, y: 88, width: aiCard.bounds.width - 24, height: 20))
        aiTitle.isBezeled = false
        aiTitle.drawsBackground = false
        aiTitle.isEditable = false
        aiTitle.stringValue = "🧠 Apple Neural Vision"
        aiTitle.font = .systemFont(ofSize: 12, weight: .bold)
        aiTitle.textColor = .white
        aiCard.addSubview(aiTitle)

        let aiDesc = NSTextField(frame: NSRect(x: 12, y: 12, width: aiCard.bounds.width - 24, height: 72))
        aiDesc.isBezeled = false
        aiDesc.drawsBackground = false
        aiDesc.isEditable = false
        aiDesc.stringValue = "Deep neural network segmentation model automatically detects the foreground subject (people, animals, art, objects) and removes the background."
        aiDesc.font = .systemFont(ofSize: 10.5)
        aiDesc.textColor = NSColor(white: 0.7, alpha: 0.9)
        aiCard.addSubview(aiDesc)

        // Original Container View
        originalContainer = NSView(frame: NSRect(x: 0, y: 58, width: sideW, height: containerH))
        originalContainer.autoresizingMask = [.minYMargin, .height]
        originalContainer.isHidden = false
        sideView.addSubview(originalContainer)

        let origCard = NSView(frame: NSRect(x: 14, y: containerH - 110, width: sideW - 28, height: 90))
        origCard.wantsLayer = true
        origCard.layer?.cornerRadius = 8
        origCard.layer?.backgroundColor = CGColor(gray: 0.18, alpha: 0.6)
        originalContainer.addSubview(origCard)

        let origTitle = NSTextField(frame: NSRect(x: 12, y: 58, width: origCard.bounds.width - 24, height: 20))
        origTitle.isBezeled = false
        origTitle.drawsBackground = false
        origTitle.isEditable = false
        origTitle.stringValue = "⭕ Original Image"
        origTitle.font = .systemFont(ofSize: 12, weight: .bold)
        origTitle.textColor = .white
        origCard.addSubview(origTitle)

        let origDesc = NSTextField(frame: NSRect(x: 12, y: 10, width: origCard.bounds.width - 24, height: 44))
        origDesc.isBezeled = false
        origDesc.drawsBackground = false
        origDesc.isEditable = false
        origDesc.stringValue = "Preserves the image and background exactly as originally formatted."
        origDesc.font = .systemFont(ofSize: 10.5)
        origDesc.textColor = NSColor(white: 0.7, alpha: 0.9)
        origCard.addSubview(origDesc)

        // Bottom Action Buttons in Sidebar
        let cancelBtn = NSButton(frame: NSRect(x: 14, y: 14, width: 80, height: 32))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.title = "Cancel"
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelClicked)
        sideView.addSubview(cancelBtn)

        saveBtn = NSButton(frame: NSRect(x: 100, y: 14, width: sideW - 114, height: 32))
        saveBtn.bezelStyle = .rounded
        saveBtn.title = "Save Sticker"
        saveBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        sideView.addSubview(saveBtn)

        // Left Center Preview Area
        let previewX: CGFloat = sideMargin
        let previewY: CGFloat = isAnimated ? (sideMargin + 42) : sideMargin
        let previewW: CGFloat = w - sideW - sideMargin * 3
        let previewH: CGFloat = isAnimated ? (h - headerH - sideMargin * 2 - 42) : (h - headerH - sideMargin * 2)

        previewView = InteractivePreviewView(frame: NSRect(x: previewX, y: previewY, width: previewW, height: previewH))
        previewView.autoresizingMask = [.width, .height]
        previewView.onSampleColor = { [weak self] r, g, b in
            guard let self = self else { return }
            self.targetColor = (r, g, b)
            self.updateColorLabels()
            self.updatePreview()
        }
        root.addSubview(previewView)

        // Playback Bar if animated
        if isAnimated {
            let bar = NSView(frame: NSRect(x: previewX, y: sideMargin, width: previewW, height: 34))
            bar.autoresizingMask = [.width, .maxYMargin]
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 8
            bar.layer?.backgroundColor = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
            bar.layer?.borderColor = CGColor(gray: 1.0, alpha: 0.08)
            bar.layer?.borderWidth = 1
            root.addSubview(bar)
            self.playbackBar = bar

            let play = NSButton(frame: NSRect(x: 6, y: 3, width: 66, height: 28))
            play.bezelStyle = .rounded
            play.title = "▶ Play"
            play.font = .systemFont(ofSize: 11, weight: .medium)
            play.target = self
            play.action = #selector(togglePlayback)
            bar.addSubview(play)
            self.playBtn = play

            let slider = NSSlider(value: 0, minValue: 0, maxValue: Double(frames.count - 1), target: self, action: #selector(frameSliderChanged))
            slider.frame = NSRect(x: 76, y: 5, width: previewW - 180, height: 22)
            slider.autoresizingMask = [.width]
            slider.numberOfTickMarks = min(frames.count, 20)
            slider.allowsTickMarkValuesOnly = false
            bar.addSubview(slider)
            self.frameSlider = slider

            let fLabel = NSTextField(frame: NSRect(x: previewW - 98, y: 7, width: 92, height: 18))
            fLabel.autoresizingMask = [.minXMargin]
            fLabel.isBezeled = false
            fLabel.drawsBackground = false
            fLabel.isEditable = false
            fLabel.alignment = .right
            fLabel.stringValue = "1 / \(frames.count)"
            fLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            fLabel.textColor = NSColor(white: 0.7, alpha: 0.9)
            bar.addSubview(fLabel)
            self.frameLabel = fLabel
        }
    }

    func updateColorLabels() {
        let r = targetColor.r
        let g = targetColor.g
        let b = targetColor.b
        let hex = String(format: "#%02X%02X%02X\nR:%d G:%d B:%d", r, g, b, r, g, b)
        hexLabel.stringValue = hex
        swatchView.layer?.backgroundColor = CGColor(srgbRed: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
        toleranceLabel.stringValue = "Color Tolerance: \(Int(tolerance * 100))%"
        featherLabel.stringValue = "Edge Feather: \(Int(smoothness * 100))%"
    }

    @objc func modeChanged() {
        cutoutMode = CutoutMode(rawValue: modeSegmented.selectedSegment) ?? .original
        colorContainer.isHidden = (cutoutMode != .colorKey)
        aiContainer.isHidden = (cutoutMode != .smartAI)
        originalContainer.isHidden = (cutoutMode != .original)
        updatePreview()
    }

    @objc func autoCornersClicked() {
        guard !frames.isEmpty else { return }
        targetColor = autoDetectCorners(cgImage: frames[currentFrameIndex])
        updateColorLabels()
        updatePreview()
    }

    @objc func toleranceChanged() {
        tolerance = toleranceSlider.floatValue / 100.0
        toleranceLabel.stringValue = "Color Tolerance: \(Int(tolerance * 100))%"
        updatePreview()
    }

    @objc func featherChanged() {
        smoothness = featherSlider.floatValue / 100.0
        featherLabel.stringValue = "Edge Feather: \(Int(smoothness * 100))%"
        updatePreview()
    }

    @objc func togglePlayback() {
        isPlaying.toggle()
        playBtn?.title = isPlaying ? "⏸ Pause" : "▶ Play"
        if isPlaying {
            startPlaybackTimer()
        } else {
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }

    func startPlaybackTimer() {
        playbackTimer?.invalidate()
        let dur = (currentFrameIndex < frameDelays.count) ? max(0.02, frameDelays[currentFrameIndex]) : 0.07
        playbackTimer = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
            self.frameSlider?.doubleValue = Double(self.currentFrameIndex)
            self.frameLabel?.stringValue = "\(self.currentFrameIndex + 1) / \(self.frames.count)"
            self.updatePreview()
            self.startPlaybackTimer()
        }
    }

    @objc func frameSliderChanged() {
        guard let slider = frameSlider else { return }
        currentFrameIndex = min(frames.count - 1, max(0, Int(round(slider.doubleValue))))
        frameLabel?.stringValue = "\(currentFrameIndex + 1) / \(frames.count)"
        updatePreview()
    }

    func updatePreview() {
        guard !frames.isEmpty, currentFrameIndex < frames.count else { return }
        let currentCG = frames[currentFrameIndex]
        var outputCG: CGImage?

        switch cutoutMode {
        case .original:
            outputCG = currentCG
        case .colorKey:
            outputCG = removeBackgroundColor(
                from: currentCG,
                targetR: targetColor.r,
                targetG: targetColor.g,
                targetB: targetColor.b,
                tolerance: tolerance,
                smoothness: smoothness
            )
        case .smartAI:
            outputCG = removeBackgroundSmartAI(from: currentCG, tolerance: tolerance, smoothness: smoothness) ?? createTransparentImage(width: currentCG.width, height: currentCG.height)
        }

        if let cg = outputCG {
            previewView.currentCGImage = cg
            previewView.imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    @objc func cancelClicked() {
        close()
    }

    @objc func saveClicked() {
        saveBtn.isEnabled = false
        saveBtn.title = "Processing…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default
            let stickersDir = (self.widgetDir as NSString).appendingPathComponent("stickers")
            try? fileManager.createDirectory(atPath: stickersDir, withIntermediateDirectories: true)
            let repoStickersDir = "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers"

            let originalFilename = URL(fileURLWithPath: self.sourcePath).lastPathComponent
            let baseName = (originalFilename as NSString).deletingPathExtension
            var cleanBase = baseName.replacingOccurrences(of: " ", with: "_")
            if cleanBase.hasSuffix("_cutout") {
                cleanBase = String(cleanBase.dropLast(7))
            }
            let suffix = (self.cutoutMode == .original) ? "" : "_cutout"
            let origExt = URL(fileURLWithPath: self.sourcePath).pathExtension.lowercased()
            let destExt = (self.cutoutMode == .original) ? (origExt.isEmpty ? "png" : origExt) : (self.isAnimated ? "gif" : "png")
            let finalName = "\(cleanBase)\(suffix).\(destExt)"
            let destPath = (stickersDir as NSString).appendingPathComponent(finalName)
            let repoDestPath = (repoStickersDir as NSString).appendingPathComponent(finalName)

            var success = false

            if self.cutoutMode == .original {
                try? fileManager.removeItem(atPath: destPath)
                try? fileManager.copyItem(at: URL(fileURLWithPath: self.sourcePath), to: URL(fileURLWithPath: destPath))
                if fileManager.fileExists(atPath: repoStickersDir) {
                    try? fileManager.removeItem(atPath: repoDestPath)
                    try? fileManager.copyItem(at: URL(fileURLWithPath: self.sourcePath), to: URL(fileURLWithPath: repoDestPath))
                }
                success = true
            } else {
                var processed: [CGImage] = []
                for frame in self.frames {
                    if self.cutoutMode == .smartAI {
                        if let out = removeBackgroundSmartAI(from: frame, tolerance: self.tolerance, smoothness: self.smoothness) {
                            processed.append(out)
                        } else if let clear = createTransparentImage(width: frame.width, height: frame.height) {
                            processed.append(clear)
                        } else {
                            processed.append(frame)
                        }
                    } else {
                        if let out = removeBackgroundColor(from: frame, targetR: self.targetColor.r, targetG: self.targetColor.g, targetB: self.targetColor.b, tolerance: self.tolerance, smoothness: self.smoothness) {
                            processed.append(out)
                        } else {
                            processed.append(frame)
                        }
                    }
                }

                if self.isAnimated {
                    success = saveAnimatedGIF(frames: processed, delays: self.frameDelays, destURL: URL(fileURLWithPath: destPath))
                    if fileManager.fileExists(atPath: repoStickersDir) {
                        _ = saveAnimatedGIF(frames: processed, delays: self.frameDelays, destURL: URL(fileURLWithPath: repoDestPath))
                    }
                } else if let first = processed.first {
                    success = saveStaticPNG(cgImage: first, destURL: URL(fileURLWithPath: destPath))
                    if fileManager.fileExists(atPath: repoStickersDir) {
                        _ = saveStaticPNG(cgImage: first, destURL: URL(fileURLWithPath: repoDestPath))
                    }
                }
            }

            if success {
                let scriptPath = (self.widgetDir as NSString).appendingPathComponent("sheet_generator.py")
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

                let relPath = "sticker.widget/stickers/\(finalName)"
                self.outputAction = "{\"action\":\"SET_STICKER\",\"instanceId\":\"\(self.instanceId)\",\"sticker\":\"\(relPath)\",\"name\":\"\(finalName)\"}"
            }

            DispatchQueue.main.async {
                self.close()
            }
        }
    }

    func showWindow() {
        playbackTimer?.invalidate()
        setupDockIcon()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func runModal() -> String? {
        isStandalone = true
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        appDelegate.getActiveWindow = { [weak self] in self?.window }
        showWindow()
        NSApp.run()
        return outputAction
    }

    private var isClosed = false
    func close() {
        guard !isClosed else { return }
        isClosed = true
        playbackTimer?.invalidate()
        playbackTimer = nil
        window.orderOut(nil)
        if isStandalone {
            NSApp.setActivationPolicy(.accessory)
        }
        onComplete?(outputAction)
        if isStandalone {
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
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}

func openStickerCutoutStudio(sourcePath: String, widgetDir: String, instanceId: String) -> String? {
    let controller = StickerCutoutStudioController(sourcePath: sourcePath, widgetDir: widgetDir, instanceId: instanceId)
    return controller.runModal()
}

// MARK: - Sticker Manager UI Components

class WindowBackgroundView: NSView {
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
    let onCutout: (StickerItem) -> Void
    let onDelete: (StickerItem) -> Void
    var isHovered: Bool = false
    var trackingArea: NSTrackingArea?

    init(item: StickerItem, frame: NSRect, onSelect: @escaping (StickerItem) -> Void, onCutout: @escaping (StickerItem) -> Void, onDelete: @escaping (StickerItem) -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onCutout = onCutout
        self.onDelete = onDelete
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        updateColors()
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateColors() {
        layer?.backgroundColor = isHovered ? CGColor(srgbRed: 0.17, green: 0.17, blue: 0.20, alpha: 1.0) : CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
        layer?.borderColor = isHovered ? CGColor(gray: 1.0, alpha: 0.24) : CGColor(gray: 1.0, alpha: 0.08)
        layer?.borderWidth = 1
    }

    func setupUI() {
        let imgView = NSImageView(frame: NSRect(x: 10, y: 34, width: bounds.width - 20, height: bounds.height - 44))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = item.image
        imgView.unregisterDraggedTypes()
        addSubview(imgView)

        let label = NSTextField(frame: NSRect(x: 6, y: 8, width: bounds.width - 12, height: 18))
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.stringValue = item.title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        if item.isInUse {
            let badge = NSTextField(frame: NSRect(x: 8, y: bounds.height - 24, width: 44, height: 16))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.backgroundColor = CGColor(srgbRed: 0.05, green: 0.48, blue: 0.98, alpha: 0.95)
            badge.isBezeled = false
            badge.drawsBackground = false
            badge.isEditable = false
            badge.isSelectable = false
            badge.stringValue = "ACTIVE"
            badge.font = .systemFont(ofSize: 8, weight: .bold)
            badge.textColor = .white
            badge.alignment = .center
            addSubview(badge)
        }

        let cutoutBtn = NSButton(frame: NSRect(x: bounds.width - 50, y: bounds.height - 26, width: 20, height: 20))
        cutoutBtn.isBordered = false
        cutoutBtn.toolTip = "Cutout & Remove Background"
        if let wandImg = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Cutout") {
            cutoutBtn.image = wandImg
            cutoutBtn.imageScaling = .scaleProportionallyDown
            cutoutBtn.contentTintColor = NSColor(white: 0.75, alpha: 0.9)
        } else {
            cutoutBtn.title = "🪄"
            cutoutBtn.font = .systemFont(ofSize: 12)
        }
        cutoutBtn.target = self
        cutoutBtn.action = #selector(cutoutClicked)
        addSubview(cutoutBtn)

        let delBtn = NSButton(frame: NSRect(x: bounds.width - 26, y: bounds.height - 26, width: 20, height: 20))
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

    @objc func cutoutClicked() {
        onCutout(item)
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
        if loc.x > bounds.width - 54 && loc.y > bounds.height - 30 {
            return
        }
        onSelect(item)
    }
}

class StickerManagerController: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    let widgetDir: String
    let instanceId: String
    let currentSticker: String?
    var autoCreateForInstance: String?

    var window: NSWindow!
    var backgroundView: WindowBackgroundView!
    var searchField: NSSearchField!
    var countLabel: NSTextField!
    var scrollView: NSScrollView!
    var gridView: NSView!
    var statusLabel: NSTextField!

    var allItems: [StickerItem] = []
    var filteredItems: [StickerItem] = []
    var outputAction: String?
    var deletedActiveSticker: Bool = false
    var activeStudio: StickerCutoutStudioController?

    init(widgetDir: String, instanceId: String, currentSticker: String?, autoCreateForInstance: String? = nil) {
        self.widgetDir = widgetDir
        self.instanceId = instanceId
        self.currentSticker = currentSticker
        self.autoCreateForInstance = autoCreateForInstance
        super.init()
        setupUI()
        loadStickers()
    }

    func openCutoutStudio(sourcePath: String) {
        let studio = StickerCutoutStudioController(sourcePath: sourcePath, widgetDir: widgetDir, instanceId: instanceId)
        studio.isStandalone = false
        studio.onComplete = { [weak self] _ in
            self?.loadStickers()
            self?.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.activeStudio = nil
        }
        self.activeStudio = studio
        studio.showWindow()
    }

    func openCutoutStudioForQuickCreate(sourcePath: String, targetInstanceId: String) {
        let studio = StickerCutoutStudioController(sourcePath: sourcePath, widgetDir: widgetDir, instanceId: targetInstanceId)
        studio.isStandalone = false
        studio.onComplete = { [weak self] resultAction in
            guard let self = self else { return }
            if let resultAction = resultAction {
                let pendingPath = (self.widgetDir as NSString).appendingPathComponent(".pending_action")
                try? resultAction.write(toFile: pendingPath, atomically: true, encoding: .utf8)
                let widgetFolder = URL(fileURLWithPath: self.widgetDir).lastPathComponent
                let widgetId = widgetFolder.replacingOccurrences(of: ".", with: "-") + "-index-jsx"
                reloadWidget(widgetId: widgetId)
            }
            self.loadStickers()
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.activeStudio = nil
        }
        self.activeStudio = studio
        studio.showWindow()
    }

    func setupUI() {
        let w: CGFloat = 640
        let h: CGFloat = 500

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 460, height: 340)
        window.maxSize = NSSize(width: 960, height: 720)
        window.title = "Sticker Library"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        window.isReleasedWhenClosed = false
        window.delegate = self

        backgroundView = WindowBackgroundView(frame: window.contentView!.bounds)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        window.contentView = backgroundView

        backgroundView.onDropFiles = { [weak self] urls in
            guard let self = self else { return }
            let allowed: Set<String> = ["webp", "gif", "png", "jpg", "jpeg"]
            let validUrls = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
            if validUrls.count == 1 {
                self.openCutoutStudio(sourcePath: validUrls[0].path)
                return
            } else {
                for url in validUrls {
                    _ = importSticker(sourcePath: url.path, widgetDir: self.widgetDir, instanceId: self.instanceId)
                }
            }
            self.loadStickers()
        }

        // Top Toolbar Header View
        let headerH: CGFloat = 48
        let headerView = NSView(frame: NSRect(x: 0, y: h - headerH, width: w, height: headerH))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)

        searchField = NSSearchField(frame: NSRect(x: 16, y: 10, width: 220, height: 28))
        searchField.placeholderString = "Search stickers…"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        headerView.addSubview(searchField)

        countLabel = NSTextField(frame: NSRect(x: 248, y: 14, width: 200, height: 20))
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.isEditable = false
        countLabel.isSelectable = false
        countLabel.textColor = NSColor(white: 0.6, alpha: 0.9)
        countLabel.font = .systemFont(ofSize: 11)
        headerView.addSubview(countLabel)

        let addBtn = NSButton(frame: NSRect(x: w - 146, y: 10, width: 130, height: 28))
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
        headerBorder.layer?.backgroundColor = CGColor(gray: 1.0, alpha: 0.08)
        headerView.addSubview(headerBorder)

        backgroundView.addSubview(headerView)

        // Scroll view & Grid
        let footerH: CGFloat = 32
        scrollView = NSScrollView(frame: NSRect(x: 0, y: footerH, width: w, height: h - headerH - footerH))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        gridView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 400))
        scrollView.documentView = gridView
        backgroundView.addSubview(scrollView)

        // Status bar footer
        let footerView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: footerH))
        footerView.autoresizingMask = [.width, .maxYMargin]
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = CGColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)

        let footerBorder = NSView(frame: NSRect(x: 0, y: footerH - 1, width: w, height: 1))
        footerBorder.autoresizingMask = [.width]
        footerBorder.wantsLayer = true
        footerBorder.layer?.backgroundColor = CGColor(gray: 1.0, alpha: 0.06)
        footerView.addSubview(footerBorder)

        statusLabel = NSTextField(frame: NSRect(x: 16, y: 7, width: w - 32, height: 18))
        statusLabel.autoresizingMask = [.width]
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(white: 0.55, alpha: 0.9)
        footerView.addSubview(statusLabel)

        backgroundView.addSubview(footerView)
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
            countLabel.stringValue = "\(allItems.count) sticker\(allItems.count == 1 ? "" : "s")"
        } else {
            filteredItems = allItems.filter { $0.title.lowercased().contains(query) }
            countLabel.stringValue = "\(filteredItems.count) of \(allItems.count)"
        }

        statusLabel.stringValue = "Drag & drop GIF, WebP, or PNG files anywhere into this window to import"
        layoutGrid()
    }

    func layoutGrid() {
        gridView.subviews.forEach { $0.removeFromSuperview() }

        if filteredItems.isEmpty {
            let msgLabel = NSTextField(frame: NSRect(x: 20, y: scrollView.contentSize.height / 2 - 25, width: scrollView.contentSize.width - 40, height: 50))
            msgLabel.isBezeled = false
            msgLabel.drawsBackground = false
            msgLabel.isEditable = false
            msgLabel.isSelectable = false
            msgLabel.alignment = .center
            msgLabel.textColor = NSColor(white: 0.55, alpha: 0.9)
            if allItems.isEmpty {
                msgLabel.stringValue = "No stickers in library yet.\nClick '+ Add Sticker…' or drag & drop GIF, WebP, or PNG files here."
            } else {
                msgLabel.stringValue = "No stickers matching \"\(searchField.stringValue)\""
            }
            msgLabel.font = .systemFont(ofSize: 13)
            gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
            gridView.addSubview(msgLabel)
            return
        }

        let cardW: CGFloat = 135
        let cardH: CGFloat = 145
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
                onCutout: { [weak self] toCutout in
                    guard let self = self else { return }
                    let stickersDir = (self.widgetDir as NSString).appendingPathComponent("stickers")
                    let fullPath = (stickersDir as NSString).appendingPathComponent(toCutout.filename)
                    self.openCutoutStudio(sourcePath: fullPath)
                },
                onDelete: { [weak self] toDelete in
                    self?.confirmDelete(toDelete)
                }
            )
            gridView.addSubview(card)
        }
    }

    func selectSticker(_ item: StickerItem) {
        // Stickers cannot be swapped from Sticker Manager.
        // Existing stickers can only be changed via Quick Switch in the context menu.
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
                let clearAction = "{\"action\":\"CLEAR_STICKER\",\"instanceId\":\"\(instanceId)\"}"
                let pendingPath = (widgetDir as NSString).appendingPathComponent(".pending_action")
                try? clearAction.write(toFile: pendingPath, atomically: true, encoding: .utf8)
                let widgetFolder = URL(fileURLWithPath: widgetDir).lastPathComponent
                let widgetId = widgetFolder.replacingOccurrences(of: ".", with: "-") + "-index-jsx"
                reloadWidget(widgetId: widgetId)
            }
            loadStickers()
        }
    }

    @objc func addStickerClicked() {
        guard let src = chooseImageFile() else { return }
        openCutoutStudio(sourcePath: src)
    }

    func showWindow() {
        isClosed = false
        setupDockIcon()
        NSApp.setActivationPolicy(.regular)
        loadStickers()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let targetInstanceId = autoCreateForInstance {
            self.autoCreateForInstance = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let src = chooseImageFile() else { return }
                self.openCutoutStudioForQuickCreate(sourcePath: src, targetInstanceId: targetInstanceId)
            }
        }
    }

    func runModal() -> String? {
        appDelegate.getActiveWindow = { [weak self] in
            return self?.activeStudio?.window ?? self?.window
        }
        appDelegate.onNewWindowRequested = { [weak self] in
            self?.showWindow()
        }
        showWindow()
        NSApp.run()
        return outputAction
    }

    private var isClosed = false
    func close() {
        guard !isClosed else { return }
        isClosed = true
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    func windowDidResize(_ notification: Notification) {
        layoutGrid()
    }
}

func openStickerManager(widgetDir: String, instanceId: String, currentSticker: String?, autoCreateForInstance: String? = nil) -> String? {
    let controller = StickerManagerController(widgetDir: widgetDir, instanceId: instanceId, currentSticker: currentSticker, autoCreateForInstance: autoCreateForInstance)
    return controller.runModal()
}

func logHelper(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: "/tmp/sticker_helper.log") {
        handle.seekToEndOfFile()
        if let d = line.data(using: .utf8) { handle.write(d) }
        try? handle.synchronize()
        handle.closeFile()
    } else {
        try? line.write(toFile: "/tmp/sticker_helper.log", atomically: true, encoding: .utf8)
    }
}

@discardableResult
func popUpMenuAtMouse(menu: NSMenu) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let mouseLoc = NSEvent.mouseLocation
    logHelper("popUpMenuAtMouse: mouseLoc=\(mouseLoc)")
    let result = menu.popUp(positioning: nil, at: mouseLoc, in: nil)
    logHelper("popUpMenuAtMouse result=\(result), outputAction=\(delegate.outputAction ?? "nil")")
    return result
}

// MARK: - Main Execution

var state = MenuState()
if CommandLine.arguments.count > 1 {
    let jsonStr = CommandLine.arguments[1]
    if let data = jsonStr.data(using: .utf8) {
        state = (try? JSONDecoder().decode(MenuState.self, from: data)) ?? MenuState()
    }
} else {
    // Opened directly with no CLI arguments (e.g. from the macOS Dock or Finder)
    state.mode = "MANAGER"
    state.instanceId = "default"
}

ProcessInfo.processInfo.processName = "Übersicht"
let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)

let delegate = MenuDelegate()
let helperPath = CommandLine.arguments[0]
var widgetDirURL = URL(fileURLWithPath: helperPath).deletingLastPathComponent()
if widgetDirURL.path.contains(".app/Contents/MacOS") {
    widgetDirURL = widgetDirURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
let widgetDir = widgetDirURL.path
let widgetFolder = widgetDirURL.lastPathComponent
let widgetId = widgetFolder.replacingOccurrences(of: ".", with: "-") + "-index-jsx"

let mode = state.mode ?? "CONTEXT_MENU"
let instanceId = state.instanceId ?? "default"
let localStickers = getLocalStickers(widgetDir: widgetDir)

logHelper("MAIN: mode=\(mode) instanceId=\(instanceId) localStickers=\(localStickers.count)")

if mode == "SYNC_DISPLAYS" || CommandLine.arguments.contains("--sync-displays") {
    let result = syncWidgetsToTargetDisplay(targetPattern: state.targetName ?? "ASUS")
    print(result)
    exit(0)
}

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

if mode == "STUDIO" {
    if let curPath = resolveStickerPath(state.currentSticker, widgetDir: widgetDir) {
        if let result = openStickerCutoutStudio(sourcePath: curPath, widgetDir: widgetDir, instanceId: instanceId) {
            print(result)
        }
    } else if let src = chooseImageFile() {
        if let result = openStickerCutoutStudio(sourcePath: src, widgetDir: widgetDir, instanceId: instanceId) {
            print(result)
        }
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

    popUpMenuAtMouse(menu: menu)

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
if !localStickers.isEmpty {
    quickSwitchMenu.addItem(NSMenuItem.separator())
}
let createNewItem = NSMenuItem(title: "+ Create New…", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
createNewItem.target = delegate
createNewItem.representedObject = "{\"action\":\"QUICK_CREATE_NEW\",\"instanceId\":\"\(instanceId)\"}"
quickSwitchMenu.addItem(createNewItem)

quickSwitchParent.submenu = quickSwitchMenu
menu.addItem(quickSwitchParent)

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
        item.representedObject = "{\"action\":\"SET_OPACITY\",\"instanceId\":\"\(instanceId)\",\"opacity\":\(val)}"
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
    item.representedObject = "{\"action\":\"\(act)\",\"instanceId\":\"\(instanceId)\"}"
    orderMenu.addItem(item)
}
orderParent.submenu = orderMenu
menu.addItem(orderParent)

if hasSticker {
    let hasShadow = state.shadow ?? true
    let shadowItem = NSMenuItem(title: "Ambient Shadow", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
    shadowItem.target = delegate
    shadowItem.representedObject = "{\"action\":\"TOGGLE_SHADOW\",\"instanceId\":\"\(instanceId)\"}"
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

// Snap Widgets to External Display
let snapDisplayItem = NSMenuItem(title: "🖥️ Snap Widgets to External Display", action: #selector(MenuDelegate.handleItem(_:)), keyEquivalent: "")
snapDisplayItem.target = delegate
snapDisplayItem.representedObject = "{\"action\":\"SNAP_TO_EXTERNAL_DISPLAY\"}"
menu.addItem(snapDisplayItem)

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
popUpMenuAtMouse(menu: menu)

if let action = delegate.outputAction {
    if action.contains("OPEN_MANAGER") {
        if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker) {
            print(result)
        }
    } else if action.contains("QUICK_CREATE_NEW") {
        if let result = openStickerManager(widgetDir: widgetDir, instanceId: instanceId, currentSticker: state.currentSticker, autoCreateForInstance: instanceId) {
            print(result)
        }
    } else if action.contains("OPEN_STUDIO") {
        if let curPath = resolveStickerPath(state.currentSticker, widgetDir: widgetDir) {
            if let result = openStickerCutoutStudio(sourcePath: curPath, widgetDir: widgetDir, instanceId: instanceId) {
                print(result)
            }
        }
    } else if action.contains("TRIGGER_FINDER_PICKER") {
        if let result = pickAndImport(widgetDir: widgetDir, instanceId: instanceId) {
            print(result)
        }
    } else if action.contains("SNAP_TO_EXTERNAL_DISPLAY") {
        let result = syncWidgetsToTargetDisplay(targetPattern: state.targetName ?? "ASUS")
        print(result)
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
