import AppKit
import ApplicationServices
import Vision

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}
func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard result == .success, let value else { throw CheckFailure(description: "Cannot read \(name): \(result.rawValue)") }
    return value
}
func find(_ element: AXUIElement, identifier: String? = nil, role: String? = nil, depth: Int = 0) -> AXUIElement? {
    let id = (try? attribute(element, kAXIdentifierAttribute)) as? String
    let elementRole = (try? attribute(element, kAXRoleAttribute)) as? String
    if (identifier == nil || id == identifier) && (role == nil || elementRole == role) { return element }
    guard depth < 18, let children = (try? attribute(element, kAXChildrenAttribute)) as? [AXUIElement] else { return nil }
    for child in children {
        if let match = find(child, identifier: identifier, role: role, depth: depth + 1) { return match }
    }
    return nil
}
func rect(_ element: AXUIElement) throws -> CGRect {
    let position = try attribute(element, kAXPositionAttribute)
    let size = try attribute(element, kAXSizeAttribute)
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    try require(CFGetTypeID(position) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID(), "Invalid accessibility geometry")
    AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
    AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions)
    return CGRect(origin: point, size: dimensions)
}
func command(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "Command failed: \(executable)")
}
@MainActor
func capture(_ id: CGWindowID, _ path: URL, region: CGRect, windowWidth: CGFloat) throws -> (Double, Data) {
    try command("/usr/sbin/screencapture", ["-x", "-o", "-l", String(id), path.path])
    let data = try Data(contentsOf: path)
    guard let bitmap = NSBitmapImageRep(data: data) else { throw CheckFailure(description: "Invalid screenshot") }
    let scale = CGFloat(bitmap.pixelsWide) / windowWidth
    var values: [Double] = []
    for y in stride(from: region.minY + 5, through: region.minY + 8, by: 1) {
        for x in stride(from: region.minX + 12, through: region.maxX - 12, by: 4) {
            let px = Int(x * scale), py = Int(y * scale)
            guard px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                  let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
            values.append(Double(0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent))
        }
    }
    try require(!values.isEmpty, "No material pixels sampled")
    return (values.reduce(0, +) / Double(values.count), data)
}
func verifyText(_ data: Data) throws {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(data: data).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined().lowercased().filter { $0.isLetter }
    try require(text.contains("restorecheck"), "Rendered search text disappeared after restoration")
}

@MainActor
func run() throws {
    try require(CommandLine.arguments.count == 2, "Usage: swift GlassWindowRestoreTests.swift <managed result directory>")
    try require(AXIsProcessTrusted(), "Window restoration checks require this terminal's existing Accessibility permission")
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let appPath = "/Applications/Bgmori.app"
    let managedTemporaryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/tmp", isDirectory: true).path + "/"
    for appearance in ["light", "dark"] {
        for route in ["categories", "library"] {
            for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier == "com.yaron.bgmori" {
                if running.bundleURL?.path == appPath || running.bundleURL?.path.hasPrefix(managedTemporaryRoot) == true { running.terminate() }
            }
            Thread.sleep(forTimeInterval: 1)
            var arguments = ["-n", "-a", appPath, "--env", "BGMORI_ROUTE=\(route)", "--env", "BGMORI_GUEST_MODE=1"]
            if route == "library" { arguments += ["--env", "BGMORI_PREVIEW_LIBRARY_FILTERS=1"] }
            try command("/usr/bin/open", arguments + ["--args", "-appearance", appearance])
            Thread.sleep(forTimeInterval: 2)
            guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == appPath }) else {
                throw CheckFailure(description: "Installed app did not launch")
            }
            try command("/usr/bin/osascript", ["-e", "tell application \"/Applications/Bgmori.app\" to activate"])
            Thread.sleep(forTimeInterval: 1)
            try require(running.isActive, "The installed app did not become active")
            let application = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 3)
            let focused = try attribute(application, kAXFocusedWindowAttribute)
            let window = unsafeBitCast(focused, to: AXUIElement.self)
            let windowRect = try rect(window)
            let stripID = route == "categories" ? "category-types" : "library-types"
            guard let strip = find(window, identifier: stripID) else { throw CheckFailure(description: "Missing \(stripID)") }
            let region = try rect(strip).offsetBy(dx: -windowRect.minX, dy: -windowRect.minY)
            if route == "library" {
                guard let field = find(window, role: kAXTextFieldRole) else { throw CheckFailure(description: "Missing search field") }
                try require(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "restore-check" as CFString) == .success,
                            "Cannot enter local search text")
            }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            guard let info = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? Int32) == running.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
            }), let number = info[kCGWindowNumber as String] as? UInt32 else { throw CheckFailure(description: "Cannot identify the visible window") }
            let baseline = try capture(number, output.appendingPathComponent("\(route)-\(appearance)-before.png"), region: region, windowWidth: windowRect.width).0
            for iteration in 1...3 {
                try command("/usr/bin/osascript", ["-e", "tell application id \"com.apple.finder\" to activate"])
                Thread.sleep(forTimeInterval: 0.6)
                try command("/usr/bin/osascript", ["-e", "tell application \"/Applications/Bgmori.app\" to activate"])
                Thread.sleep(forTimeInterval: 1)
                try require(running.isActive, "The original app did not return to the foreground")
                let restored = try capture(number, output.appendingPathComponent("\(route)-\(appearance)-activated-\(iteration).png"), region: region, windowWidth: windowRect.width)
                try require(abs(restored.0 - baseline) < 0.14, "Material changed after activation: \(baseline) -> \(restored.0)")
                if appearance == "light" { try require(restored.0 > 0.72, "Light glass became dark") }
                if route == "library" { try verifyText(restored.1) }
            }
            try require(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success, "Cannot minimize the existing window")
            Thread.sleep(forTimeInterval: 0.6)
            try require(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success, "Cannot restore the existing window")
            try command("/usr/bin/osascript", ["-e", "tell application \"/Applications/Bgmori.app\" to activate"])
            Thread.sleep(forTimeInterval: 1)
            try require(running.isActive, "Restored application did not become active")
            let visibleWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            try require(visibleWindows.contains { ($0[kCGWindowNumber as String] as? UInt32) == number },
                        "The original window did not return onscreen")
            let restored = try capture(number, output.appendingPathComponent("\(route)-\(appearance)-restored.png"), region: region, windowWidth: windowRect.width)
            try require(abs(restored.0 - baseline) < 0.14, "Material changed after restoration: \(baseline) -> \(restored.0)")
            if appearance == "light" { try require(restored.0 > 0.72, "Restored light glass became dark") }
            if route == "library" { try verifyText(restored.1) }
            print("PASS \(route) \(appearance): same window \(number), material \(String(format: "%.3f", baseline)) -> \(String(format: "%.3f", restored.0))")
            running.terminate()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

MainActor.assumeIsolated {
    do { try run() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
