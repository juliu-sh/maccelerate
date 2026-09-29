import AppKit
import Carbon
import Combine
import Foundation

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String
  var keyEquivalent: String

  var displayString: String {
    let modifierSymbols = HotkeyCombination.symbols(for: modifiers)
    return modifierSymbols + displayKey
  }

  var cocoaModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
  }

  var cgEventFlagsRawValue: UInt64 {
    var flags: CGEventFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
    return flags.rawValue
  }

  var isValid: Bool {
    !displayKey.isEmpty
  }

  func hasSameBinding(as other: HotkeyCombination) -> Bool {
    let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    return keyCode == other.keyCode && (modifiers & mask) == (other.modifiers & mask)
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.leftArrow)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.rightArrow)
  )

  static let defaultMissionControl = HotkeyCombination(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(controlKey),
    displayKey: "↑",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.upArrow)
  )

  static let defaultAppExpose = HotkeyCombination(
    keyCode: UInt32(kVK_DownArrow),
    modifiers: UInt32(controlKey),
    displayKey: "↓",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.downArrow)
  )

  static let defaultLastSpace = HotkeyCombination(
    keyCode: UInt32(kVK_ANSI_KeypadPlus),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "↩",
    keyEquivalent: "-" 
  )

  static func defaultForSpace(_ number: Int) -> HotkeyCombination {
    let keyCode: UInt32
    let displayKey: String
    let keyEquivalent: String

    switch number {
    case 1:
      keyCode = UInt32(kVK_ANSI_1)
      displayKey = "1"
      keyEquivalent = "1"
    case 2:
      keyCode = UInt32(kVK_ANSI_2)
      displayKey = "2"
      keyEquivalent = "2"
    case 3:
      keyCode = UInt32(kVK_ANSI_3)
      displayKey = "3"
      keyEquivalent = "3"
    case 4:
      keyCode = UInt32(kVK_ANSI_4)
      displayKey = "4"
      keyEquivalent = "4"
    case 5:
      keyCode = UInt32(kVK_ANSI_5)
      displayKey = "5"
      keyEquivalent = "5"
    case 6:
      keyCode = UInt32(kVK_ANSI_6)
      displayKey = "6"
      keyEquivalent = "6"
    case 7:
      keyCode = UInt32(kVK_ANSI_7)
      displayKey = "7"
      keyEquivalent = "7"
    case 8:
      keyCode = UInt32(kVK_ANSI_8)
      displayKey = "8"
      keyEquivalent = "8"
    case 9:
      keyCode = UInt32(kVK_ANSI_9)
      displayKey = "9"
      keyEquivalent = "9"
    case 10:
      keyCode = UInt32(kVK_ANSI_0)
      displayKey = "0"
      keyEquivalent = "0"
    default: fatalError("Invalid space number")
    }

    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: defaultModifierMask,
      displayKey: displayKey,
      keyEquivalent: keyEquivalent
    )
  }

  static func from(event: NSEvent) -> HotkeyCombination? {
    let modifiers = event.modifierFlags.carbonMask
    let keyCode = UInt32(event.keyCode)
    
    // Handle arrow keys
    if let special = event.specialKey, let symbol = arrowSymbol(for: special) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: symbol,
        keyEquivalent: arrowKeyEquivalent(special)
      )
    }
    
    // Handle special keys (Enter, F-keys, etc.)
    if let (displayKey, keyEquiv) = specialKeyInfo(for: Int(event.keyCode)) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: displayKey,
        keyEquivalent: keyEquiv
      )
    }

    guard let characters = event.charactersIgnoringModifiers, let first = characters.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }

    let upper = String(first).uppercased()
    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: modifiers,
      displayKey: upper,
      keyEquivalent: String(first).lowercased()
    )
  }

  static func arrowSymbol(for specialKey: NSEvent.SpecialKey) -> String? {
    switch specialKey {
    case .leftArrow: return "←"
    case .rightArrow: return "→"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return nil
    }
  }
  
  private static func specialKeyInfo(for keyCode: Int) -> (displayKey: String, keyEquivalent: String)? {
    switch keyCode {
    // Enter/Return
    case kVK_Return:
      return ("↩", String(Character(UnicodeScalar(NSCarriageReturnCharacter)!)))
    case kVK_ANSI_KeypadEnter:
      return ("⌅", String(Character(UnicodeScalar(NSEnterCharacter)!)))
    // Tab
    case kVK_Tab:
      return ("⇥", String(Character(UnicodeScalar(NSTabCharacter)!)))
    // Delete/Backspace
    case kVK_Delete:
      return ("⌫", String(Character(UnicodeScalar(NSBackspaceCharacter)!)))
    case kVK_ForwardDelete:
      return ("⌦", String(Character(UnicodeScalar(NSDeleteCharacter)!)))
    // Space
    case kVK_Space:
      return ("Space", " ")
    // F-keys
    case kVK_F1:
      return ("F1", String(Character(UnicodeScalar(NSF1FunctionKey)!)))
    case kVK_F2:
      return ("F2", String(Character(UnicodeScalar(NSF2FunctionKey)!)))
    case kVK_F3:
      return ("F3", String(Character(UnicodeScalar(NSF3FunctionKey)!)))
    case kVK_F4:
      return ("F4", String(Character(UnicodeScalar(NSF4FunctionKey)!)))
    case kVK_F5:
      return ("F5", String(Character(UnicodeScalar(NSF5FunctionKey)!)))
    case kVK_F6:
      return ("F6", String(Character(UnicodeScalar(NSF6FunctionKey)!)))
    case kVK_F7:
      return ("F7", String(Character(UnicodeScalar(NSF7FunctionKey)!)))
    case kVK_F8:
      return ("F8", String(Character(UnicodeScalar(NSF8FunctionKey)!)))
    case kVK_F9:
      return ("F9", String(Character(UnicodeScalar(NSF9FunctionKey)!)))
    case kVK_F10:
      return ("F10", String(Character(UnicodeScalar(NSF10FunctionKey)!)))
    case kVK_F11:
      return ("F11", String(Character(UnicodeScalar(NSF11FunctionKey)!)))
    case kVK_F12:
      return ("F12", String(Character(UnicodeScalar(NSF12FunctionKey)!)))
    // Home/End/Page
    case kVK_Home:
      return ("↖", String(Character(UnicodeScalar(NSHomeFunctionKey)!)))
    case kVK_End:
      return ("↘", String(Character(UnicodeScalar(NSEndFunctionKey)!)))
    case kVK_PageUp:
      return ("⇞", String(Character(UnicodeScalar(NSPageUpFunctionKey)!)))
    case kVK_PageDown:
      return ("⇟", String(Character(UnicodeScalar(NSPageDownFunctionKey)!)))
    default:
      return nil
    }
  }

  private static func arrowKeyEquivalent(_ specialKey: NSEvent.SpecialKey) -> String {
    switch specialKey {
    case .leftArrow:
      return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case .rightArrow:
      return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case .upArrow:
      return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case .downArrow:
      return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    default:
      return ""
    }
  }

  private static func symbols(for modifiers: UInt32) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  private static var defaultModifierMask: UInt32 {
    UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
  }
}

enum HotkeyIdentifier: String, CaseIterable {
  case left
  case right
  case missionControl
  case appExpose
  case space1, space2, space3, space4, space5
  case space6, space7, space8, space9, space10
  case lastSpace
  
  var displayName: String {
    switch self {
    case .left: return "Switch to space on the left"
    case .right: return "Switch to space on the right"
    case .missionControl: return "Mission Control"
    case .appExpose: return "App Exposé"
    case .space1: return "Switch to space 1"
    case .space2: return "Switch to space 2"
    case .space3: return "Switch to space 3"
    case .space4: return "Switch to space 4"
    case .space5: return "Switch to space 5"
    case .space6: return "Switch to space 6"
    case .space7: return "Switch to space 7"
    case .space8: return "Switch to space 8"
    case .space9: return "Switch to space 9"
    case .space10: return "Switch to space 10"
    case .lastSpace: return "Switch to last used space"
    }
  }
}

extension HotkeyIdentifier {
  var defaultCombination: HotkeyCombination {
    switch self {
    case .left: return .defaultLeft
    case .right: return .defaultRight
    case .missionControl: return .defaultMissionControl
    case .appExpose: return .defaultAppExpose
    case .lastSpace: return .defaultLastSpace
    case .space1: return .defaultForSpace(1)
    case .space2: return .defaultForSpace(2)
    case .space3: return .defaultForSpace(3)
    case .space4: return .defaultForSpace(4)
    case .space5: return .defaultForSpace(5)
    case .space6: return .defaultForSpace(6)
    case .space7: return .defaultForSpace(7)
    case .space8: return .defaultForSpace(8)
    case .space9: return .defaultForSpace(9)
    case .space10: return .defaultForSpace(10)
    }
  }
}

struct HotkeyConflict: Error, Equatable {
  let requested: HotkeyIdentifier
  let existing: HotkeyIdentifier

  var message: String {
    "Already used by \(existing.displayName). Choose another shortcut."
  }
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  // Emit only after a complete accepted mutation, including a bulk reset.
  let configurationDidChange = PassthroughSubject<Void, Never>()

  @Published private(set) var leftHotkey: HotkeyCombination
  @Published private(set) var rightHotkey: HotkeyCombination
  @Published private(set) var missionControlHotkey: HotkeyCombination
  @Published private(set) var appExposeHotkey: HotkeyCombination
  @Published private(set) var space1Hotkey: HotkeyCombination
  @Published private(set) var space2Hotkey: HotkeyCombination
  @Published private(set) var space3Hotkey: HotkeyCombination
  @Published private(set) var space4Hotkey: HotkeyCombination
  @Published private(set) var space5Hotkey: HotkeyCombination
  @Published private(set) var space6Hotkey: HotkeyCombination
  @Published private(set) var space7Hotkey: HotkeyCombination
  @Published private(set) var space8Hotkey: HotkeyCombination
  @Published private(set) var space9Hotkey: HotkeyCombination
  @Published private(set) var space10Hotkey: HotkeyCombination
  @Published private(set) var spaceLastSpaceHotkey: HotkeyCombination
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    leftHotkey = defaults.hotkey(forKey: DefaultsKey.left.rawValue) ?? .defaultLeft
    rightHotkey = defaults.hotkey(forKey: DefaultsKey.right.rawValue) ?? .defaultRight
    missionControlHotkey = defaults.hotkey(forKey: DefaultsKey.missionControl.rawValue)
      ?? .defaultMissionControl
    appExposeHotkey = defaults.hotkey(forKey: DefaultsKey.appExpose.rawValue) ?? .defaultAppExpose
    space1Hotkey = defaults.hotkey(forKey: DefaultsKey.space1.rawValue) ?? .defaultForSpace(1)
    space2Hotkey = defaults.hotkey(forKey: DefaultsKey.space2.rawValue) ?? .defaultForSpace(2)
    space3Hotkey = defaults.hotkey(forKey: DefaultsKey.space3.rawValue) ?? .defaultForSpace(3)
    space4Hotkey = defaults.hotkey(forKey: DefaultsKey.space4.rawValue) ?? .defaultForSpace(4)
    space5Hotkey = defaults.hotkey(forKey: DefaultsKey.space5.rawValue) ?? .defaultForSpace(5)
    space6Hotkey = defaults.hotkey(forKey: DefaultsKey.space6.rawValue) ?? .defaultForSpace(6)
    space7Hotkey = defaults.hotkey(forKey: DefaultsKey.space7.rawValue) ?? .defaultForSpace(7)
    space8Hotkey = defaults.hotkey(forKey: DefaultsKey.space8.rawValue) ?? .defaultForSpace(8)
    space9Hotkey = defaults.hotkey(forKey: DefaultsKey.space9.rawValue) ?? .defaultForSpace(9)
    space10Hotkey = defaults.hotkey(forKey: DefaultsKey.space10.rawValue) ?? .defaultForSpace(10)
    spaceLastSpaceHotkey = defaults.hotkey(forKey: DefaultsKey.lastSpace.rawValue) ?? .defaultLastSpace

    for identifier in HotkeyIdentifier.allCases {
      let key = "enabled.\(identifier.rawValue)"
      enabledStates[identifier] = defaults.object(forKey: key) as? Bool ?? true
    }
  }

  private func conflict(for identifier: HotkeyIdentifier,
                        combination: HotkeyCombination) -> HotkeyConflict? {
    guard let existing = HotkeyIdentifier.allCases.first(where: {
      $0 != identifier && isEnabled($0) && self.combination(for: $0).hasSameBinding(as: combination)
    }) else { return nil }
    return HotkeyConflict(requested: identifier, existing: existing)
  }

  // Report old conflicting settings without migrating them or changing priority.
  var activeConflicts: [HotkeyConflict] {
    var seen: [HotkeyIdentifier] = []
    var conflicts: [HotkeyConflict] = []
    for identifier in HotkeyIdentifier.allCases where isEnabled(identifier) {
      if let existing = seen.first(where: {
        combination(for: $0).hasSameBinding(as: combination(for: identifier))
      }) {
        conflicts.append(HotkeyConflict(requested: identifier, existing: existing))
      }
      seen.append(identifier)
    }
    return conflicts
  }

  var conflictWarning: String? {
    guard let first = activeConflicts.first else { return nil }
    return "Shortcut conflict: \(first.requested.displayName) / \(first.existing.displayName). Change or disable one."
  }

  @discardableResult
  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier)
    -> Result<Void, HotkeyConflict> {
    if isEnabled(identifier), let conflict = conflict(for: identifier, combination: combination) {
      return .failure(conflict)
    }
    guard combination != self.combination(for: identifier) else { return .success(()) }
    apply(combination, for: identifier)
    configurationDidChange.send()
    return .success(())
  }

  @discardableResult
  func resetShortcut(for identifier: HotkeyIdentifier) -> Result<Void, HotkeyConflict> {
    update(identifier.defaultCombination, for: identifier)
  }

  private func apply(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    switch identifier {
    case .left:
      guard combination != leftHotkey else { return }
      leftHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.left.rawValue)
    case .right:
      guard combination != rightHotkey else { return }
      rightHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.right.rawValue)
    case .missionControl:
      guard combination != missionControlHotkey else { return }
      missionControlHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.missionControl.rawValue)
    case .appExpose:
      guard combination != appExposeHotkey else { return }
      appExposeHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.appExpose.rawValue)
    case .space1:
      guard combination != space1Hotkey else { return }
      space1Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space1.rawValue)
    case .space2:
      guard combination != space2Hotkey else { return }
      space2Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space2.rawValue)
    case .space3:
      guard combination != space3Hotkey else { return }
      space3Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space3.rawValue)
    case .space4:
      guard combination != space4Hotkey else { return }
      space4Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space4.rawValue)
    case .space5:
      guard combination != space5Hotkey else { return }
      space5Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space5.rawValue)
    case .space6:
      guard combination != space6Hotkey else { return }
      space6Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space6.rawValue)
    case .space7:
      guard combination != space7Hotkey else { return }
      space7Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space7.rawValue)
    case .space8:
      guard combination != space8Hotkey else { return }
      space8Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space8.rawValue)
    case .space9:
      guard combination != space9Hotkey else { return }
      space9Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space9.rawValue)
    case .space10:
      guard combination != space10Hotkey else { return }
      space10Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space10.rawValue)
    case .lastSpace:
      guard combination != spaceLastSpaceHotkey else { return }
      spaceLastSpaceHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.lastSpace.rawValue)
    }
  }

  func resetToDefaults() {
    leftHotkey = .defaultLeft
    rightHotkey = .defaultRight
    missionControlHotkey = .defaultMissionControl
    appExposeHotkey = .defaultAppExpose
    space1Hotkey = .defaultForSpace(1)
    space2Hotkey = .defaultForSpace(2)
    space3Hotkey = .defaultForSpace(3)
    space4Hotkey = .defaultForSpace(4)
    space5Hotkey = .defaultForSpace(5)
    space6Hotkey = .defaultForSpace(6)
    space7Hotkey = .defaultForSpace(7)
    space8Hotkey = .defaultForSpace(8)
    space9Hotkey = .defaultForSpace(9)
    space10Hotkey = .defaultForSpace(10)
    spaceLastSpaceHotkey = .defaultLastSpace

    defaults.setHotkey(leftHotkey, forKey: DefaultsKey.left.rawValue)
    defaults.setHotkey(rightHotkey, forKey: DefaultsKey.right.rawValue)
    defaults.setHotkey(missionControlHotkey, forKey: DefaultsKey.missionControl.rawValue)
    defaults.setHotkey(appExposeHotkey, forKey: DefaultsKey.appExpose.rawValue)
    defaults.setHotkey(space1Hotkey, forKey: DefaultsKey.space1.rawValue)
    defaults.setHotkey(space2Hotkey, forKey: DefaultsKey.space2.rawValue)
    defaults.setHotkey(space3Hotkey, forKey: DefaultsKey.space3.rawValue)
    defaults.setHotkey(space4Hotkey, forKey: DefaultsKey.space4.rawValue)
    defaults.setHotkey(space5Hotkey, forKey: DefaultsKey.space5.rawValue)
    defaults.setHotkey(space6Hotkey, forKey: DefaultsKey.space6.rawValue)
    defaults.setHotkey(space7Hotkey, forKey: DefaultsKey.space7.rawValue)
    defaults.setHotkey(space8Hotkey, forKey: DefaultsKey.space8.rawValue)
    defaults.setHotkey(space9Hotkey, forKey: DefaultsKey.space9.rawValue)
    defaults.setHotkey(space10Hotkey, forKey: DefaultsKey.space10.rawValue)
    defaults.setHotkey(spaceLastSpaceHotkey, forKey: DefaultsKey.lastSpace.rawValue)
    configurationDidChange.send()
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    switch identifier {
    case .left: return leftHotkey
    case .right: return rightHotkey
    case .missionControl: return missionControlHotkey
    case .appExpose: return appExposeHotkey
    case .space1: return space1Hotkey
    case .space2: return space2Hotkey
    case .space3: return space3Hotkey
    case .space4: return space4Hotkey
    case .space5: return space5Hotkey
    case .space6: return space6Hotkey
    case .space7: return space7Hotkey
    case .space8: return space8Hotkey
    case .space9: return space9Hotkey
    case .space10: return space10Hotkey
    case .lastSpace: return spaceLastSpaceHotkey
    }
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    return enabledStates[identifier] ?? true
  }

  @discardableResult
  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) -> Result<Void, HotkeyConflict> {
    if enabled, let conflict = conflict(for: identifier, combination: combination(for: identifier)) {
      return .failure(conflict)
    }
    guard enabled != isEnabled(identifier) else { return .success(()) }
    enabledStates[identifier] = enabled
    let key = "enabled.\(identifier.rawValue)"
    defaults.set(enabled, forKey: key)
    configurationDidChange.send()
    return .success(())
  }

  private enum DefaultsKey: String {
    case left = "hotkey.left"
    case right = "hotkey.right"
    case missionControl = "hotkey.missionControl"
    case appExpose = "hotkey.appExpose"
    case space1 = "hotkey.space1"
    case space2 = "hotkey.space2"
    case space3 = "hotkey.space3"
    case space4 = "hotkey.space4"
    case space5 = "hotkey.space5"
    case space6 = "hotkey.space6"
    case space7 = "hotkey.space7"
    case space8 = "hotkey.space8"
    case space9 = "hotkey.space9"
    case space10 = "hotkey.space10"
    case lastSpace = "hotkey.lastSpace"
  }
}

extension UserDefaults {
  fileprivate func hotkey(forKey key: String) -> HotkeyCombination? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
  }

  fileprivate func setHotkey(_ hotkey: HotkeyCombination, forKey key: String) {
    if let data = try? JSONEncoder().encode(hotkey) {
      set(data, forKey: key)
    }
  }
}

extension NSEvent.ModifierFlags {
  var carbonMask: UInt32 {
    var mask: UInt32 = 0
    if contains(.command) { mask |= UInt32(cmdKey) }
    if contains(.option) { mask |= UInt32(optionKey) }
    if contains(.control) { mask |= UInt32(controlKey) }
    if contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
  }
}
