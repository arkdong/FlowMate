import Foundation
#if os(macOS)
import ApplicationServices

enum AccessibilityPermission {
    static func ensure(prompt: Bool = true) {
        let granted = AXIsProcessTrusted()
        guard !granted, prompt else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }
}
#endif
