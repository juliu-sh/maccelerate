import Foundation
import ISS

/// System leaves Space switching, ⌘ Tab, swipes and macOS's shortcuts to macOS.
/// A preset lets Maccelerate accelerate them. Choosing System keeps the stored
/// preset, so switching back restores it and older releases keep working.
enum SwitchingMode: Equatable {
  case system
  case preset(SwitchingSpeedPreset)

  static let accelerationKey = "accelerationEnabled"
  static let speedKey = "gestureSpeed"
  static let didChange = Notification.Name("MaccelerateSwitchingModeChanged")
  /// Segment order in Settings and the menu bar panel.
  static let titles = ["System"] + SwitchingSpeedPreset.allCases.map(\.title)

  var segment: Int {
    switch self {
    case .system: return 0
    case .preset(let preset): return preset.rawValue + 1
    }
  }

  init?(segment: Int) {
    if segment == 0 {
      self = .system
    } else if let preset = SwitchingSpeedPreset(rawValue: segment - 1) {
      self = .preset(preset)
    } else {
      return nil
    }
  }

  var accelerates: Bool { self != .system }

  /// Maccelerate's own shortcuts have no macOS animation to fall back to, so
  /// under System they move at the gentlest preset.
  var velocity: Double {
    switch self {
    case .system: return SwitchingSpeedPreset.fast.velocity
    case .preset(let preset): return preset.velocity
    }
  }

  static func current(_ defaults: UserDefaults = .standard) -> SwitchingMode {
    guard defaults.object(forKey: accelerationKey) as? Bool ?? true else { return .system }
    let stored = (defaults.object(forKey: speedKey) as? NSNumber)?.doubleValue ?? 0
    return .preset(SwitchingSpeedPreset.fromStoredVelocity(stored))
  }

  static func store(_ mode: SwitchingMode, in defaults: UserDefaults = .standard) {
    defaults.set(mode.accelerates, forKey: accelerationKey)
    if case .preset(let preset) = mode { defaults.set(preset.velocity, forKey: speedKey) }
  }

  /// Saves the choice, applies it and lets Settings and the menu bar panel follow.
  static func select(_ mode: SwitchingMode) {
    store(mode)
    apply()
    NotificationCenter.default.post(name: didChange, object: nil)
  }

  /// Pushes the stored mode and the swipe switch into the event tap.
  static func apply() {
    let mode = current()
    iss_set_gesture_speed(mode.velocity)
    iss_set_swipe_override(mode.accelerates && UserDefaults.standard.bool(forKey: "swipeOverride"))
    iss_set_overlay_acceleration(mode.accelerates)
  }
}
