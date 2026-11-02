import AppKit
import ApplicationServices

/// Experimental: Shift-click on a Dock icon adds the app to the current
/// Stage Manager stage instead of switching to the app's own stage.
///
/// macOS offers no setting for this. WindowManager exposes every entry of the
/// recent-apps strip as an accessibility button with an "Add to Stage" action
/// (VoiceOver uses it) and the IDs of the entry's windows. Nothing is written
/// to macOS; without a matching strip entry the Dock gets the click unchanged.
enum StageDockClick {
  static let enabledKey = "stageDockShiftClick"
  private static let addToStageAction = "AXAddToStage" as CFString
  private static let windowIDsAttribute = "AXWindowsIDs" as CFString
  // Bounds the time the event tap waits for the Dock or WindowManager.
  private static let messagingTimeout: Float = 0.2

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  /// Called from the event tap for a physical Shift-click. Returns true when
  /// the click adds an app to the stage and must not reach the Dock.
  static func handle(at location: CGPoint) -> Bool {
    guard isEnabled, StageManagerTuning.isStageManagerEnabled,
      let pid = dockApplication(at: location),
      let entry = stripEntry(for: pid)
    else { return false }
    // Leave the tap first; WindowManager animates the change.
    DispatchQueue.main.async { _ = AXUIElementPerformAction(entry, addToStageAction) }
    return true
  }

  /// Prefers an entry holding only the app's windows, otherwise the first
  /// entry with one of them. Strip order follows recent use.
  static func preferredEntry(for pid: pid_t, entries: [[CGWindowID]],
                             owners: [CGWindowID: pid_t]) -> Int? {
    let containing = entries.indices.filter { index in
      entries[index].contains { owners[$0] == pid }
    }
    let onlyApp = containing.first { index in
      entries[index].allSatisfy { owners[$0] == pid }
    }
    return onlyApp ?? containing.first
  }

  /// The running app whose Dock icon is under the pointer.
  private static func dockApplication(at location: CGPoint) -> pid_t? {
    guard let dock = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.dock").first
    else { return nil }
    let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(dockElement, messagingTimeout)
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(
      dockElement, Float(location.x), Float(location.y), &hit) == .success,
      let hit,
      value(hit, kAXSubroleAttribute as CFString) as? String == "AXApplicationDockItem",
      let url = (value(hit, kAXURLAttribute as CFString) as? URL)?.standardizedFileURL
    else { return nil }
    return NSWorkspace.shared.runningApplications.first {
      !$0.isTerminated && $0.bundleURL?.standardizedFileURL == url
    }?.processIdentifier
  }

  private static func stripEntry(for pid: pid_t) -> AXUIElement? {
    guard let windowManager = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.WindowManager").first
    else { return nil }
    let root = AXUIElementCreateApplication(windowManager.processIdentifier)
    AXUIElementSetMessagingTimeout(root, messagingTimeout)
    var entries: [(element: AXUIElement, windows: [CGWindowID])] = []
    collectEntries(root, depth: 0, into: &entries)
    guard !entries.isEmpty else { return nil }
    let index = preferredEntry(for: pid, entries: entries.map(\.windows),
                               owners: windowOwners())
    return index.map { entries[$0].element }
  }

  /// Strip entries sit at application → display group → list → button.
  private static func collectEntries(
    _ element: AXUIElement, depth: Int,
    into entries: inout [(element: AXUIElement, windows: [CGWindowID])]
  ) {
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success,
      (actions as? [String])?.contains(addToStageAction as String) == true,
      let ids = value(element, windowIDsAttribute) as? [NSNumber] {
      entries.append((element, ids.map { CGWindowID($0.uint32Value) }))
      return
    }
    guard depth < 4,
      let children = value(element, kAXChildrenAttribute as CFString) as? [AXUIElement]
    else { return }
    for child in children { collectEntries(child, depth: depth + 1, into: &entries) }
  }

  /// Window numbers and owners only; no titles or contents are read.
  private static func windowOwners() -> [CGWindowID: pid_t] {
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
    var owners: [CGWindowID: pid_t] = [:]
    for window in windows {
      guard let id = window[kCGWindowNumber as String] as? NSNumber,
        let owner = window[kCGWindowOwnerPID as String] as? NSNumber
      else { continue }
      owners[CGWindowID(id.uint32Value)] = pid_t(owner.int32Value)
    }
    return owners
  }

  private static func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var result: AnyObject?
    return AXUIElementCopyAttributeValue(element, attribute, &result) == .success ? result : nil
  }
}
