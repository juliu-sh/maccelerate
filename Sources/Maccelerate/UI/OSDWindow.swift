import AppKit
import ISS

/// Stored indicator settings. `showOSD` and `osdDurationMs` keep their names from earlier releases.
enum IndicatorSettings {
  static let enabledKey = "showOSD"
  static let durationKey = "osdDurationMs"
  static let styleKey = "indicatorStyle"
  static let shadowKey = "indicatorShadow"
  static let shadowShapeKey = "indicatorShadowShape"
  static let positionKey = "indicatorPosition"
  static let durations = [250, 500, 750]

  /// Earlier releases offered 100 to 1000 ms; each maps to the nearest remaining choice.
  static func duration(fromStored value: Int?) -> Int {
    guard let value else { return durations[0] }
    let clamped = min(max(value, durations[0]), durations[durations.count - 1])
    return durations.min { abs($0 - clamped) < abs($1 - clamped) } ?? durations[0]
  }

  /// Someone who already used Maccelerate keeps the indicator they know.
  static func defaultStyle(existingInstall: Bool) -> IndicatorStyle {
    existingInstall ? .card : .dots
  }

  /// Writes the new keys once, so later defaults can change without moving anyone.
  static func migrate(_ defaults: UserDefaults = .standard) {
    if defaults.object(forKey: styleKey) == nil {
      let existing = ["showOSD", "osdDurationMs", "gestureSpeed", "SUHasLaunchedBefore"]
        .contains { defaults.object(forKey: $0) != nil }
      defaults.set(defaultStyle(existingInstall: existing).rawValue, forKey: styleKey)
    }
    let stored = defaults.object(forKey: durationKey) as? Int
    let duration = duration(fromStored: stored)
    if stored != duration { defaults.set(duration, forKey: durationKey) }
  }
}

/// The indicator's settings and the window that shows it on screen.
@MainActor
final class SpaceIndicator {
  static let shared = SpaceIndicator()
  private let defaults = UserDefaults.standard
  private var window: NSWindow?
  private var hideTimer: Timer?
  private var presentationID = 0

  var isOn: Bool {
    get { defaults.bool(forKey: IndicatorSettings.enabledKey) }
    set { defaults.set(newValue, forKey: IndicatorSettings.enabledKey) }
  }
  var style: IndicatorStyle {
    get { IndicatorStyle(rawValue: defaults.integer(forKey: IndicatorSettings.styleKey)) ?? .card }
    set { defaults.set(newValue.rawValue, forKey: IndicatorSettings.styleKey) }
  }
  var durationMs: Int {
    get { IndicatorSettings.duration(fromStored: defaults.object(forKey: IndicatorSettings.durationKey) as? Int) }
    set { defaults.set(newValue, forKey: IndicatorSettings.durationKey) }
  }
  var shadow: IndicatorShadow {
    get { (defaults.object(forKey: IndicatorSettings.shadowKey) as? Int).flatMap(IndicatorShadow.init) ?? .medium }
    set { defaults.set(newValue.rawValue, forKey: IndicatorSettings.shadowKey) }
  }
  var shadowShape: IndicatorShadowShape {
    get {
      (defaults.object(forKey: IndicatorSettings.shadowShapeKey) as? Int).flatMap(IndicatorShadowShape.init)
        ?? .layered
    }
    set { defaults.set(newValue.rawValue, forKey: IndicatorSettings.shadowShapeKey) }
  }
  var position: IndicatorPosition {
    get {
      (defaults.object(forKey: IndicatorSettings.positionKey) as? Int).flatMap(IndicatorPosition.init(index:))
        ?? .standard
    }
    set { defaults.set(newValue.index, forKey: IndicatorSettings.positionKey) }
  }

  /// The live Space, or a sample when Spaces cannot be read.
  private var spaceInfo: (space: Int, total: Int) {
    var info = ISSSpaceInfo()
    guard iss_get_menubar_space_info(&info), info.spaceCount > 0 else { return (2, 5) }
    return (Int(info.currentIndex) + 1, Int(info.spaceCount))
  }

  /// After a Space switch. Hidden while Mission Control covers the screen.
  func show(space: Int) {
    guard isOn else { return }
    let detection = defaults.object(forKey: "overlayDetectionEnabled") as? Bool ?? true
    if detection && iss_is_mission_control_active() { return }
    present(space: space, total: max(spaceInfo.total, space), seconds: nil)
  }

  /// From Settings: also while the indicator is off, so a choice can be judged before turning it on.
  func preview(seconds: Double? = nil) {
    let info = spaceInfo
    present(space: info.space, total: info.total, seconds: seconds)
  }

  private func present(space: Int, total: Int, seconds: Double?) {
    hideTimer?.invalidate()
    presentationID += 1
    let hud = SpaceIndicatorView(style: style, space: space, total: total)
    hud.shadowLevel = shadow
    hud.shadowShape = shadowShape
    let window = self.window ?? makeWindow()
    self.window = window
    window.setContentSize(hud.intrinsicContentSize)
    window.contentView = hud
    let mouse = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
      let origin = position.origin(for: style.size(total: total), in: screen.visibleFrame)
      window.setFrameOrigin(NSPoint(x: origin.x - SpaceIndicatorView.shadowRoom,
                                    y: origin.y - SpaceIndicatorView.shadowRoom))
    }
    window.alphaValue = 1
    window.orderFrontRegardless()
    let delay = seconds ?? Double(durationMs) / 1000
    hideTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, delay), repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in self?.hide() }
    }
  }

  private func hide() {
    let id = presentationID
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
      window?.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.presentationID == id else { return }
        self.window?.orderOut(nil)
      }
    }
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    return window
  }
}
