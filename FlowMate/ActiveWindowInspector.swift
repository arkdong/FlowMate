import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
import OSLog

final class ActiveWindowInspector {
    private let logger = Logger(subsystem: "FlowMate.ActiveWindowInspector", category: "Tracking")
    private let snippetLimit = 400

    func captureContext(for application: NSRunningApplication) -> ActivityContext {
        let defaultTitle = application.localizedName ?? "Unknown App"
        let timestamp = Date()
        guard AccessibilityPermission.isGranted else {
            return ActivityContext(windowTitle: defaultTitle,
                                   url: nil,
                                   documentPath: nil,
                                   contentSnippet: nil,
                                   capturedAt: timestamp)
        }

        let bundleID = application.bundleIdentifier ?? ""
        let info = focusedWindowInfo(for: application)
        let title = info.title ?? defaultTitle
        let trackedApp = TrackedApp(bundleIdentifier: bundleID)

        switch trackedApp {
        case .chrome:
            if let chrome = chromeContext(defaultTitle: title) {
                return chrome
            }
        case .obsidian, .vscode, .vscodeInsiders:
            if let fileContext = fileBasedContext(title: title, documentAttribute: info.documentPath) {
                return fileContext
            }
        case .unsupported:
            break
        }

        return ActivityContext(windowTitle: title,
                               url: info.documentPath.flatMap { URL(fileURLWithPath: $0) },
                               documentPath: info.documentPath,
                               contentSnippet: nil,
                               capturedAt: timestamp)
    }

    private func chromeContext(defaultTitle: String) -> ActivityContext? {
        guard let tabInfo = fetchChromeTabInfo() else { return nil }
        let url = URL(string: tabInfo.url)
        let windowTitle = tabInfo.title.isEmpty ? defaultTitle : tabInfo.title
        return ActivityContext(windowTitle: windowTitle,
                               url: url,
                               documentPath: nil,
                               contentSnippet: nil,
                               capturedAt: Date())
    }

    private func fileBasedContext(title: String, documentAttribute: String?) -> ActivityContext? {
        guard let fileURL = normalizedFileURL(from: documentAttribute) else { return nil }
        let snippet = snippetFromFile(fileURL)
        return ActivityContext(windowTitle: title,
                               url: fileURL,
                               documentPath: fileURL.path,
                               contentSnippet: snippet,
                               capturedAt: Date())
    }

    private func snippetFromFile(_ url: URL) -> String? {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            logger.debug("Unable to read file at \(url.path, privacy: .public)")
            return nil
        }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let snippet = trimmed.prefix(snippetLimit)
        return String(snippet)
    }

    private func normalizedFileURL(from attribute: String?) -> URL? {
        guard let attribute, !attribute.isEmpty else { return nil }
        if attribute.hasPrefix("file://") {
            let trimmed = attribute.replacingOccurrences(of: "file://", with: "")
            return URL(fileURLWithPath: trimmed)
        }
        return URL(fileURLWithPath: attribute)
    }

    private func fetchChromeTabInfo() -> (title: String, url: String)? {
        let script = """
        tell application "Google Chrome"
            if (count of windows) = 0 then return {"", "", ""}
            set activeTab to active tab of front window
            set tabTitle to title of activeTab
            set tabURL to URL of activeTab
            return {tabTitle, tabURL}
        end tell
        """
        guard let values = executeListAppleScript(script), values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    private func focusedWindowInfo(for application: NSRunningApplication) -> (title: String?, documentPath: String?) {
        guard let window = focusedWindow(for: application) else { return (nil, nil) }
        let title = stringValue(attribute: kAXTitleAttribute as CFString, from: window)
        let document = stringValue(attribute: kAXDocumentAttribute as CFString, from: window)
        return (title, document)
    }

    private func focusedWindow(for application: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var window: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window)
        guard error == .success, let value = window else { return nil }
        return (value as! AXUIElement)
    }

    private func stringValue(attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let cfValue = value else { return nil }
        return cfValue as? String
    }

    private func executeListAppleScript(_ script: String) -> [String]? {
        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        guard let result = appleScript?.executeAndReturnError(&errorDict), errorDict == nil else {
            if let error = errorDict {
                logger.error("AppleScript error: \(error)")
            }
            return nil
        }
        var values: [String] = []
        if result.numberOfItems > 0 {
            for index in 1...result.numberOfItems {
                values.append(result.atIndex(index)?.stringValue ?? "")
            }
        } else if let value = result.stringValue {
            values.append(value)
        }
        return values
    }
}

private enum TrackedApp {
    case chrome
    case obsidian
    case vscode
    case vscodeInsiders
    case unsupported

    init(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.google.Chrome":
            self = .chrome
        case "md.obsidian":
            self = .obsidian
        case "com.microsoft.VSCode":
            self = .vscode
        case "com.microsoft.VSCodeInsiders":
            self = .vscodeInsiders
        default:
            self = .unsupported
        }
    }
}
#endif
