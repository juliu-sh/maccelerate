import Foundation

/// Stage Manager animation presets. The values are written to the hidden
/// `AnimationSpeed` preference of macOS's WindowManager; higher is faster.
enum StageManagerSpeed: Int, CaseIterable {
  case system, fast, faster, instant

  var title: String {
    switch self {
    case .system: return "System"
    case .fast: return "Fast"
    case .faster: return "Faster"
    case .instant: return "Instant"
    }
  }

  /// nil removes the preference, which restores the macOS default.
  var animationSpeed: Double? {
    switch self {
    case .system: return nil
    case .fast: return 2
    case .faster: return 4
    case .instant: return 100
    }
  }

  /// Returns nil for a value set outside Maccelerate that matches no preset.
  static func from(storedValue: Double?) -> StageManagerSpeed? {
    guard let storedValue else { return .system }
    return allCases.first { $0.animationSpeed == storedValue }
  }
}

/// Undocumented WindowManager preferences that change Stage Manager timing.
/// They are system settings: they stay in macOS after Maccelerate quits or is
/// removed, and a macOS update can ignore them. Nothing is written unless the
/// user changes a setting.
enum StageManagerTuning {
  private static let domain = "com.apple.WindowManager" as CFString
  private static let animationSpeedKey = "AnimationSpeed" as CFString
  private static let autoHideDelayKey = "AutoHideDelay" as CFString

  static var isStageManagerEnabled: Bool { bool("GloballyEnabled") ?? false }
  /// Whether recent apps are hidden until the pointer reaches the screen edge.
  static var hidesRecentApps: Bool { bool("AutoHide") ?? false }

  static var speed: StageManagerSpeed? {
    StageManagerSpeed.from(storedValue: double(animationSpeedKey))
  }

  static func setSpeed(_ speed: StageManagerSpeed) {
    write(speed.animationSpeed, for: animationSpeedKey)
  }

  static var showsRecentAppsInstantly: Bool { double(autoHideDelayKey) == 0 }

  static func setShowsRecentAppsInstantly(_ enabled: Bool) {
    write(enabled ? 0 : nil, for: autoHideDelayKey)
  }

  /// Makes WindowManager reread `AutoHideDelay`; `AnimationSpeed` applies
  /// immediately. Its launch agent relaunches it.
  @discardableResult
  static func restartStageManager() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["WindowManager"]
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  private static func write(_ value: Double?, for key: CFString) {
    CFPreferencesSetAppValue(key, value.map { NSNumber(value: $0) }, domain)
    CFPreferencesAppSynchronize(domain)
  }

  private static func double(_ key: CFString) -> Double? {
    CFPreferencesAppSynchronize(domain)
    return (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.doubleValue
  }

  private static func bool(_ key: String) -> Bool? {
    CFPreferencesAppSynchronize(domain)
    return (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.boolValue
  }
}
