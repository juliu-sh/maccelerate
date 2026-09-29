import AppKit
import Carbon
import Combine
import Testing
@testable import Maccelerate

// Never read or write the user's preferences, including from failed tests.
final class MemoryDefaults: UserDefaults {
  var values: [String: Any] = [:]
  override func object(forKey key: String) -> Any? { values[key] }
  override func data(forKey key: String) -> Data? { values[key] as? Data }
  override func set(_ value: Any?, forKey key: String) { values[key] = value }
  override func set(_ value: Bool, forKey key: String) { values[key] = value }
}

@Suite("Hotkey conflict protection")
struct HotkeyStoreTests {
  @Test func enablingPreviouslyDisabledDuplicateIsRejected() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    store.setEnabled(false, for: .appExpose)
    store.update(.defaultAppExpose, for: .missionControl)
    let before = defaults.values as NSDictionary
    let result = store.setEnabled(true, for: .appExpose)
    if case .failure(let conflict) = result {
      #expect(conflict == HotkeyConflict(requested: .appExpose, existing: .missionControl))
    } else {
      Issue.record("Expected a typed activation conflict")
    }
    #expect(!store.isEnabled(.appExpose))
    #expect(store.missionControlHotkey == .defaultAppExpose)
    #expect(before.isEqual(to: defaults.values))
  }

  @Test func updatingAnActiveShortcutToAnOccupiedBindingIsRejected() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    let before = defaults.values as NSDictionary
    store.update(.defaultAppExpose, for: .missionControl)
    #expect(store.missionControlHotkey == .defaultMissionControl)
    #expect(before.isEqual(to: defaults.values))
  }

  @Test func displayMetadataDoesNotHideAConflict() {
    let store = HotkeyStore(defaults: MemoryDefaults())
    var duplicate = HotkeyCombination.defaultAppExpose
    duplicate.displayKey = "Down"
    duplicate.keyEquivalent = "different label"
    duplicate.modifiers |= UInt32(alphaLock)
    store.update(duplicate, for: .missionControl)
    #expect(store.missionControlHotkey == .defaultMissionControl)
  }

  @Test func singleResetRejectsConflictWithoutPublishingOrSaving() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    let custom = HotkeyCombination(keyCode: 0, modifiers: UInt32(controlKey),
                                   displayKey: "A", keyEquivalent: "a")
    store.update(custom, for: .missionControl)
    store.update(.defaultMissionControl, for: .appExpose)
    let before = defaults.values as NSDictionary
    var notifications = 0
    let subscription = store.configurationDidChange.sink { notifications += 1 }
    let result = store.resetShortcut(for: .missionControl)
    if case .failure(let conflict) = result {
      #expect(conflict.existing == .appExpose)
    } else {
      Issue.record("Expected a typed reset conflict")
    }
    #expect(store.missionControlHotkey == custom)
    #expect(before.isEqual(to: defaults.values))
    #expect(notifications == 0)
    withExtendedLifetime(subscription) {}
  }

  @Test func rejectedUpdateAndActivationPublishNoChanges() {
    let store = HotkeyStore(defaults: MemoryDefaults())
    store.setEnabled(false, for: .left)
    store.update(.defaultRight, for: .left)
    var notifications = 0
    var propertyChanges = 0
    let subscription = store.configurationDidChange.sink { notifications += 1 }
    let observation = store.objectWillChange.sink { propertyChanges += 1 }
    store.update(.defaultAppExpose, for: .missionControl)
    store.setEnabled(true, for: .left)
    #expect(notifications == 0)
    #expect(propertyChanges == 0)
    withExtendedLifetime((subscription, observation)) {}
  }

  @Test func disabledBindingsAreRetainedAndCanBeReenabledAfterConflictIsRemoved() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    store.setEnabled(false, for: .appExpose)
    store.update(.defaultMissionControl, for: .appExpose)
    #expect(store.appExposeHotkey == .defaultMissionControl)
    #expect(store.activeConflicts.isEmpty)
    let reloaded = HotkeyStore(defaults: defaults)
    #expect(!reloaded.isEnabled(.appExpose))
    #expect(reloaded.appExposeHotkey == .defaultMissionControl)
    reloaded.setEnabled(false, for: .missionControl)
    let result = reloaded.setEnabled(true, for: .appExpose)
    if case .failure = result { Issue.record("The binding is now available") }
    #expect(reloaded.isEnabled(.appExpose))
  }

  @Test func selfAssignmentIsANoopAndDifferentModifiersAreAllowed() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    var notifications = 0
    let subscription = store.configurationDidChange.sink { notifications += 1 }
    store.update(.defaultMissionControl, for: .missionControl)
    store.setEnabled(true, for: .missionControl)
    #expect(defaults.values.isEmpty)
    #expect(notifications == 0)
    var custom = HotkeyCombination.defaultAppExpose
    custom.modifiers = UInt32(optionKey)
    let result = store.update(custom, for: .missionControl)
    if case .failure = result { Issue.record("Different modifiers are not a conflict") }
    #expect(store.missionControlHotkey == custom)
    #expect(notifications == 1)
    #expect(HotkeyStore(defaults: defaults).missionControlHotkey == custom)
    store.resetShortcut(for: .missionControl)
    #expect(store.missionControlHotkey == .defaultMissionControl)
    withExtendedLifetime(subscription) {}
  }

  @Test func bulkResetPublishesOnlyTheFinalStateAndRetainsDisabledActions() {
    let defaults = MemoryDefaults()
    let store = HotkeyStore(defaults: defaults)
    store.setEnabled(false, for: .appExpose)
    store.update(.defaultAppExpose, for: .missionControl)
    store.update(.defaultMissionControl, for: .appExpose)
    store.setEnabled(true, for: .appExpose)
    store.setEnabled(false, for: .space4)
    var notifications = 0
    let subscription = store.configurationDidChange.sink {
      notifications += 1
      #expect(store.activeConflicts.isEmpty)
      #expect(!store.isEnabled(.space4))
      for identifier in HotkeyIdentifier.allCases {
        #expect(store.combination(for: identifier) == identifier.defaultCombination)
      }
      let reloaded = HotkeyStore(defaults: defaults)
      for identifier in HotkeyIdentifier.allCases {
        #expect(reloaded.combination(for: identifier) == identifier.defaultCombination)
      }
    }
    store.resetToDefaults()
    #expect(notifications == 1)
    withExtendedLifetime(subscription) {}
  }

  @Test func oldConflictsAreReportedWithoutMigrationOrPriorityChanges() throws {
    let defaults = MemoryDefaults()
    defaults.set(try JSONEncoder().encode(HotkeyCombination.defaultAppExpose),
                 forKey: "hotkey.missionControl")
    let before = defaults.values as NSDictionary
    let store = HotkeyStore(defaults: defaults)
    #expect(store.activeConflicts == [HotkeyConflict(requested: .appExpose, existing: .missionControl)])
    #expect(store.conflictWarning != nil)
    #expect(store.isEnabled(.missionControl) && store.isEnabled(.appExpose))
    #expect(before.isEqual(to: defaults.values))
    store.setEnabled(false, for: .appExpose)
    #expect(store.conflictWarning == nil)
  }

  @Test func retryingAnOldConflictingBindingDoesNotReportSuccess() throws {
    let defaults = MemoryDefaults()
    defaults.set(try JSONEncoder().encode(HotkeyCombination.defaultAppExpose),
                 forKey: "hotkey.missionControl")
    let before = defaults.values as NSDictionary
    let store = HotkeyStore(defaults: defaults)
    for result in [store.resetShortcut(for: .appExpose),
                   store.setEnabled(true, for: .appExpose)] {
      if case .failure(let conflict) = result {
        #expect(conflict.existing == .missionControl)
      } else {
        Issue.record("An existing conflict must not be reported as successfully resolved")
      }
    }
    #expect(before.isEqual(to: defaults.values))
  }
}
