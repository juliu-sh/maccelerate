import ISS
import Testing
@testable import Maccelerate

// Parses literal dictionaries only; never reads the user's system shortcuts.
@Suite("macOS shortcuts")
struct SystemSpaceShortcutsTests {
  private let control: UInt64 = 262_144

  private func entry(_ enabled: Any, _ keyCode: Int, _ modifiers: Int) -> [String: Any] {
    ["enabled": enabled, "value": ["type": "standard", "parameters": [65535, keyCode, modifiers]]]
  }

  @Test func missingEntriesUseMacOSDefaults() {
    let result = SystemSpaceShortcuts.enabled(in: [:])
    #expect(result.count == 2)
    #expect(result[ISSSystemShortcutLeft] == SystemSpaceShortcut(keyCode: 123, modifiers: control))
    #expect(result[ISSSystemShortcutRight] == SystemSpaceShortcut(keyCode: 124, modifiers: control))
  }

  @Test func disabledShortcutsStayWithTheFrontmostApp() {
    let result = SystemSpaceShortcuts.enabled(in: [
      "79": entry(false, 123, 262_144),
      "81": ["enabled": "0"],
    ])
    #expect(result.isEmpty)
  }

  @Test func customBindingsAndDesktopShortcutsAreRead() {
    let result = SystemSpaceShortcuts.enabled(in: [
      "79": entry(true, 0, 1_310_720),
      "118": entry(true, 18, 262_144),
      "127": entry(1, 29, 262_144),
      "119": entry(false, 19, 262_144),
    ])
    #expect(result[ISSSystemShortcutLeft] == SystemSpaceShortcut(keyCode: 0, modifiers: 1_310_720))
    #expect(result[ISSSystemShortcutRight] == SystemSpaceShortcut(keyCode: 124, modifiers: control))
    #expect(result[ISSSystemShortcutDesktop1] == SystemSpaceShortcut(keyCode: 18, modifiers: control))
    let desktop10 = ISSSystemShortcut(rawValue: ISSSystemShortcutDesktop1.rawValue + 9)
    #expect(result[desktop10] == SystemSpaceShortcut(keyCode: 29, modifiers: control))
    #expect(result.count == 4)
  }

  @Test func shortcutsWithoutAKeyAreIgnored() {
    let result = SystemSpaceShortcuts.enabled(in: [
      "79": entry(true, 65535, 262_144),
      "81": ["enabled": true, "value": ["parameters": [65535]]],
    ])
    #expect(result.isEmpty)
  }

  @Test func overlayShortcutsDefaultToControlArrows() {
    let result = SystemSpaceShortcuts.overlays(in: [:])
    #expect(result[ISSOverlayModeMissionControl] == SystemSpaceShortcut(keyCode: 126, modifiers: control))
    #expect(result[ISSOverlayModeAppExpose] == SystemSpaceShortcut(keyCode: 125, modifiers: control))
  }

  @Test func overlayShortcutsFollowSystemSettings() {
    let result = SystemSpaceShortcuts.overlays(in: [
      "32": entry(true, 46, 1_048_576),
      "33": entry(false, 125, 262_144),
    ])
    #expect(result[ISSOverlayModeMissionControl] == SystemSpaceShortcut(keyCode: 46, modifiers: 1_048_576))
    #expect(result[ISSOverlayModeAppExpose] == nil)
  }

  @Test func summaryListsEnabledShortcuts() {
    var bindings = SystemSpaceShortcuts.Bindings()
    #expect(SystemSpaceShortcuts.summary(of: bindings) == "None are enabled in System Settings.")
    bindings.spaces = SystemSpaceShortcuts.enabled(in: [:])
    bindings.overlays = SystemSpaceShortcuts.overlays(in: ["33": entry(false, 125, 262_144)])
    // The fn bit macOS stores for arrow keys is not shown.
    bindings.spaces[ISSSystemShortcutDesktop1] = SystemSpaceShortcut(keyCode: 126, modifiers: 8_650_752)
    #expect(SystemSpaceShortcuts.summary(of: bindings)
      == "Spaces ⌃← ⌃→ · Mission Control ⌃↑ · Desktops ⌃↑")
  }

  @Test func symbolicIdentifiersMatchSystemSettings() {
    #expect(SystemSpaceShortcuts.symbolicID(for: ISSSystemShortcutLeft) == 79)
    #expect(SystemSpaceShortcuts.symbolicID(for: ISSSystemShortcutRight) == 81)
    #expect(SystemSpaceShortcuts.symbolicID(for: ISSSystemShortcutDesktop1) == 118)
    #expect(SystemSpaceShortcuts.allShortcuts.count == 12)
    #expect(SystemSpaceShortcuts.symbolicID(for: ISSOverlayModeMissionControl) == 32)
    #expect(SystemSpaceShortcuts.symbolicID(for: ISSOverlayModeAppExpose) == 33)
  }
}

@Suite("Stage Manager presets")
struct StageManagerSpeedTests {
  @Test func storedValuesMapToPresets() {
    #expect(StageManagerSpeed.from(storedValue: nil) == .system)
    #expect(StageManagerSpeed.from(storedValue: 2) == .fast)
    #expect(StageManagerSpeed.from(storedValue: 4) == .faster)
    #expect(StageManagerSpeed.from(storedValue: 100) == .instant)
    #expect(StageManagerSpeed.from(storedValue: 3) == nil)
  }

  @Test func systemRemovesThePreference() {
    #expect(StageManagerSpeed.system.animationSpeed == nil)
    #expect(StageManagerSpeed.allCases.compactMap(\.animationSpeed) == [2, 4, 100])
  }
}

@Suite("Stage Dock click")
struct StageDockClickTests {
  @Test func prefersAnEntryWithOnlyTheAppsWindows() {
    let owners: [CGWindowID: pid_t] = [1: 10, 2: 20, 3: 10, 4: 10]
    #expect(StageDockClick.preferredEntry(for: 10, entries: [[1, 2], [3, 4]], owners: owners) == 1)
  }

  @Test func fallsBackToAGroupContainingTheApp() {
    let owners: [CGWindowID: pid_t] = [1: 10, 2: 20, 3: 30]
    #expect(StageDockClick.preferredEntry(for: 10, entries: [[3], [2, 1]], owners: owners) == 1)
  }

  @Test func appWithoutAStripEntryKeepsTheDockClick() {
    let owners: [CGWindowID: pid_t] = [1: 20, 5: 10]
    #expect(StageDockClick.preferredEntry(for: 10, entries: [[1], [2]], owners: owners) == nil)
    #expect(StageDockClick.preferredEntry(for: 10, entries: [], owners: owners) == nil)
  }
}
