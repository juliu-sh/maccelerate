import Carbon
import Foundation
import ISS

/// macOS's own shortcuts from System Settings → Keyboard → Keyboard Shortcuts
/// → Mission Control. Only shortcuts enabled there are accelerated; a disabled
/// combination such as ⌃← belongs to the frontmost app and is never consumed.
struct SystemSpaceShortcut: Equatable {
  /// Carbon key code, identical to CGKeyCode.
  var keyCode: UInt16
  /// NSEvent/CGEventFlags bits; both use the same device-independent layout.
  var modifiers: UInt64

  var displayString: String {
    let flags = CGEventFlags(rawValue: modifiers)
    var result = ""
    if flags.contains(.maskControl) { result += "⌃" }
    if flags.contains(.maskAlternate) { result += "⌥" }
    if flags.contains(.maskShift) { result += "⇧" }
    if flags.contains(.maskCommand) { result += "⌘" }
    return result + SystemSpaceShortcuts.keyName(keyCode)
  }
}

enum SystemSpaceShortcuts {
  /// The enabled macOS shortcuts Maccelerate accelerates.
  struct Bindings: Equatable {
    var spaces: [ISSSystemShortcut: SystemSpaceShortcut] = [:]
    var overlays: [ISSOverlayMode: SystemSpaceShortcut] = [:]
  }

  static let enabledKey = "accelerateSystemShortcuts"
  private static let domain = "com.apple.symbolichotkeys" as CFString
  private static let hotkeysKey = "AppleSymbolicHotKeys" as CFString
  private static let control: UInt64 = 1 << 18

  /// Symbolic hotkey IDs: 79/81 move left/right a space, 118... switch to Desktop N.
  static func symbolicID(for shortcut: ISSSystemShortcut) -> Int {
    switch shortcut {
    case ISSSystemShortcutLeft: return 79
    case ISSSystemShortcutRight: return 81
    default: return 118 + Int(shortcut.rawValue - ISSSystemShortcutDesktop1.rawValue)
    }
  }

  /// Symbolic hotkey IDs: 32 Mission Control, 33 Application windows.
  static func symbolicID(for mode: ISSOverlayMode) -> Int {
    mode == ISSOverlayModeMissionControl ? 32 : 33
  }

  static var allShortcuts: [ISSSystemShortcut] {
    (0..<ISSSystemShortcutCount.rawValue).map { ISSSystemShortcut(rawValue: $0) }
  }

  static let overlayModes = [ISSOverlayModeMissionControl, ISSOverlayModeAppExpose]

  static var isAccelerationEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  /// Reads the live system configuration.
  static func current() -> Bindings {
    CFPreferencesAppSynchronize(domain)
    let hotkeys = CFPreferencesCopyAppValue(hotkeysKey, domain) as? [String: Any] ?? [:]
    return Bindings(spaces: enabled(in: hotkeys), overlays: overlays(in: hotkeys))
  }

  /// Entries missing from the plist use macOS defaults: ⌃← and ⌃→ enabled,
  /// Desktop shortcuts disabled.
  static func enabled(in hotkeys: [String: Any]) -> [ISSSystemShortcut: SystemSpaceShortcut] {
    var result: [ISSSystemShortcut: SystemSpaceShortcut] = [:]
    for shortcut in allShortcuts {
      let fallback: SystemSpaceShortcut?
      switch shortcut {
      case ISSSystemShortcutLeft: fallback = SystemSpaceShortcut(keyCode: 123, modifiers: control)
      case ISSSystemShortcutRight: fallback = SystemSpaceShortcut(keyCode: 124, modifiers: control)
      default: fallback = nil
      }
      result[shortcut] = binding(symbolicID(for: shortcut), fallback: fallback, in: hotkeys)
    }
    return result
  }

  /// Missing entries use macOS defaults: ⌃↑ and ⌃↓, both enabled.
  static func overlays(in hotkeys: [String: Any]) -> [ISSOverlayMode: SystemSpaceShortcut] {
    var result: [ISSOverlayMode: SystemSpaceShortcut] = [:]
    for mode in overlayModes {
      let keyCode: UInt16 = mode == ISSOverlayModeMissionControl ? 126 : 125
      result[mode] = binding(symbolicID(for: mode),
                             fallback: SystemSpaceShortcut(keyCode: keyCode, modifiers: control),
                             in: hotkeys)
    }
    return result
  }

  /// One line for Settings, e.g. "Spaces ⌃← ⌃→ · Mission Control ⌃↑".
  static func summary(of bindings: Bindings) -> String {
    var parts: [String] = []
    let moves = [ISSSystemShortcutLeft, ISSSystemShortcutRight].compactMap { bindings.spaces[$0] }
    if !moves.isEmpty { parts.append("Spaces " + moves.map(\.displayString).joined(separator: " ")) }
    if let binding = bindings.overlays[ISSOverlayModeMissionControl] {
      parts.append("Mission Control " + binding.displayString)
    }
    if let binding = bindings.overlays[ISSOverlayModeAppExpose] {
      parts.append("App Exposé " + binding.displayString)
    }
    let desktops = allShortcuts.dropFirst(2).compactMap { bindings.spaces[$0] }
    if !desktops.isEmpty { parts.append("Desktops " + desktops.map(\.displayString).joined(separator: " ")) }
    return parts.isEmpty ? "None are enabled in System Settings." : parts.joined(separator: " · ")
  }

  static func keyName(_ keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_DownArrow: return "↓"
    case kVK_UpArrow: return "↑"
    default: break
    }
    if let special = HotkeyCombination.specialKeyInfo(for: Int(keyCode)) { return special.displayKey }
    return typedCharacter(keyCode)?.uppercased() ?? "Key \(keyCode)"
  }

  private static func typedCharacter(_ keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var deadKeys: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = layout.withUnsafeBytes { bytes -> OSStatus in
      guard let base = bytes.baseAddress else { return -1 }
      return UCKeyTranslate(
        base.assumingMemoryBound(to: UCKeyboardLayout.self), keyCode,
        UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
        characters.count, &length, &characters)
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
  }

  private static func binding(_ id: Int, fallback: SystemSpaceShortcut?,
                              in hotkeys: [String: Any]) -> SystemSpaceShortcut? {
    let entry = hotkeys[String(id)] as? [String: Any]
    guard boolValue(entry?["enabled"]) ?? (fallback != nil) else { return nil }
    if let value = entry?["value"] { return parse(value) }
    return fallback
  }

  private static func parse(_ value: Any) -> SystemSpaceShortcut? {
    guard let value = value as? [String: Any],
      let parameters = value["parameters"] as? [Any], parameters.count >= 3,
      let keyCode = intValue(parameters[1]), let modifiers = intValue(parameters[2]),
      (0..<0xFFFF).contains(keyCode), modifiers >= 0
    else { return nil }
    return SystemSpaceShortcut(keyCode: UInt16(keyCode), modifiers: UInt64(modifiers))
  }

  private static func intValue(_ value: Any) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String { return Int(text) }
    return nil
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber { return number.boolValue }
    if let text = value as? String { return text != "0" && text.lowercased() != "false" }
    return nil
  }
}
