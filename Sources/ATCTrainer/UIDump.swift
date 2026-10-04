import AppKit

/// Test hook (RT_DUMP_UI=1): prints the visible window contents as an accessibility tree so CI
/// can check what's on screen without screenshots.
@MainActor
enum UIDump {
    static func dump(_ header: String) {
        print("===== UI DUMP: \(header)")
        for window in NSApp.windows where window.isVisible {
            print("WINDOW '\(window.title)' \(Int(window.frame.width))x\(Int(window.frame.height))")
            if let view = window.contentView { walk(view, depth: 1) }
        }
        print("===== END UI DUMP")
        fflush(stdout)
    }

    private static func walk(_ element: Any, depth: Int) {
        guard depth < 60, let e = element as? NSAccessibilityProtocol else { return }
        var parts: [String] = [e.accessibilityRole()?.rawValue ?? "?"]
        if let label = e.accessibilityLabel(), !label.isEmpty { parts.append("label=\"\(label)\"") }
        if let title = e.accessibilityTitle(), !title.isEmpty { parts.append("title=\"\(title)\"") }
        if let value = e.accessibilityValue() { parts.append("value=\"\(value)\"") }
        let f = e.accessibilityFrame()
        parts.append("[\(Int(f.width))x\(Int(f.height))]")
        print(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        for child in e.accessibilityChildren() ?? [] { walk(child, depth: depth + 1) }
    }
}
