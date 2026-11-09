import AppKit

func syncWidgetsToTargetDisplay(targetPattern: String = "ASUS") -> String {
    let screens = NSScreen.screens
    var targetScreen: NSScreen? = nil

    for s in screens {
        if s.localizedName.localizedCaseInsensitiveContains(targetPattern) {
            targetScreen = s
            break
        }
    }

    if targetScreen == nil {
        for s in screens {
            if s.frame.height > s.frame.width {
                targetScreen = s
                break
            }
        }
    }

    if targetScreen == nil && screens.count > 1 {
        targetScreen = screens.first(where: { $0 != NSScreen.main })
    }

    if targetScreen == nil {
        targetScreen = NSScreen.main
    }

    guard let foundScreen = targetScreen else {
        return "{\"status\":\"skipped\",\"reason\":\"No display connected\"}"
    }

    let screenNumber = foundScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

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
            "showOnAllScreens": true,
            "showOnMainScreen": false,
            "showOnSelectedScreens": false,
            "hidden": false,
            "screens": []
        ]

        let curAll = (currentSetting["showOnAllScreens"] as? Bool) ?? false
        let curHidden = (currentSetting["hidden"] as? Bool) ?? false

        if !curAll || curHidden {
            currentSetting["showOnAllScreens"] = true
            currentSetting["showOnMainScreen"] = false
            currentSetting["showOnSelectedScreens"] = false
            currentSetting["hidden"] = false
            currentSetting["screens"] = []
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

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ASUS"
let result = syncWidgetsToTargetDisplay(targetPattern: target)
print(result)
