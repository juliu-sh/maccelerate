import AppKit
import Testing
@testable import Maccelerate

// Keeps every value in memory, whichever setter the code under test uses.
private final class ScratchDefaults: UserDefaults {
  var values: [String: Any] = [:]
  override func object(forKey key: String) -> Any? { values[key] }
  override func set(_ value: Any?, forKey key: String) { values[key] = value }
  override func set(_ value: Bool, forKey key: String) { values[key] = value }
  override func set(_ value: Int, forKey key: String) { values[key] = value }
  override func set(_ value: Double, forKey key: String) { values[key] = value }
  override func removeObject(forKey key: String) { values[key] = nil }
}

@Suite("Switching mode")
struct SwitchingModeTests {
  @Test func segmentsRoundTrip() {
    #expect(SwitchingMode.titles == ["System", "Fast", "Faster", "Instant"])
    for segment in 0..<SwitchingMode.titles.count {
      #expect(SwitchingMode(segment: segment)?.segment == segment)
    }
    #expect(SwitchingMode(segment: 4) == nil)
    #expect(SwitchingMode(segment: -1) == nil)
  }

  @Test func earlierReleasesStillAccelerate() {
    let defaults = ScratchDefaults()
    #expect(SwitchingMode.current(defaults) == .preset(.instant))
    defaults.values["gestureSpeed"] = 400.0
    #expect(SwitchingMode.current(defaults) == .preset(.faster))
  }

  @Test func systemKeepsTheChosenPreset() {
    let defaults = ScratchDefaults()
    SwitchingMode.store(.preset(.faster), in: defaults)
    SwitchingMode.store(.system, in: defaults)
    #expect(SwitchingMode.current(defaults) == .system)
    #expect(defaults.values["gestureSpeed"] as? Double == 400)
    defaults.values["accelerationEnabled"] = true
    #expect(SwitchingMode.current(defaults) == .preset(.faster))
  }

  @Test func ownShortcutsUnderSystemUseTheGentlestPreset() {
    #expect(!SwitchingMode.system.accelerates)
    #expect(SwitchingMode.system.velocity == SwitchingSpeedPreset.fast.velocity)
    #expect(SwitchingMode.preset(.instant).velocity == 1000)
  }
}

@Suite("Space indicator settings")
struct IndicatorSettingsTests {
  @Test func durationsMoveToTheNearestChoice() {
    let expected = [100: 250, 200: 250, 250: 250, 300: 250, 500: 500, 750: 750, 1000: 750]
    for (stored, duration) in expected {
      #expect(IndicatorSettings.duration(fromStored: stored) == duration)
    }
    #expect(IndicatorSettings.duration(fromStored: nil) == 250)
    #expect(IndicatorSettings.duration(fromStored: Int.min) == 250)
    #expect(IndicatorSettings.duration(fromStored: Int.max) == 750)
  }

  @Test func newInstallsStartWithDotsAndExistingOnesKeepTheCard() {
    let fresh = ScratchDefaults()
    IndicatorSettings.migrate(fresh)
    #expect(fresh.values["indicatorStyle"] as? Int == IndicatorStyle.dots.rawValue)
    #expect(fresh.values["osdDurationMs"] as? Int == 250)

    let existing = ScratchDefaults()
    existing.values["showOSD"] = true
    existing.values["osdDurationMs"] = 1000
    IndicatorSettings.migrate(existing)
    #expect(existing.values["indicatorStyle"] as? Int == IndicatorStyle.card.rawValue)
    #expect(existing.values["osdDurationMs"] as? Int == 750)
  }

  @Test func migrationRunsOnce() {
    let defaults = ScratchDefaults()
    defaults.values["indicatorStyle"] = IndicatorStyle.tiles.rawValue
    defaults.values["gestureSpeed"] = 1000.0
    IndicatorSettings.migrate(defaults)
    #expect(defaults.values["indicatorStyle"] as? Int == IndicatorStyle.tiles.rawValue)
  }
}

@Suite("Space indicator layout")
struct IndicatorLayoutTests {
  @Test func fifteenPlacesRoundTrip() {
    #expect(IndicatorPosition.all.count == 15)
    for (index, position) in IndicatorPosition.all.enumerated() {
      #expect(position.index == index)
      #expect(IndicatorPosition(index: index) == position)
    }
    #expect(IndicatorPosition(index: 15) == nil)
    #expect(IndicatorPosition.standard.index == 13)
  }

  @Test func placesStayInsideTheVisibleFrame() {
    let frame = NSRect(x: 100, y: 40, width: 1440, height: 860)
    let size = NSSize(width: 196, height: 60)
    let bottomCentre = IndicatorPosition.standard.origin(for: size, in: frame)
    #expect(bottomCentre == NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 64))
    for position in IndicatorPosition.all {
      let rect = NSRect(origin: position.origin(for: size, in: frame), size: size)
      #expect(frame.insetBy(dx: 63, dy: 63).contains(rect))
    }
  }

  @Test func tilesWrapAfterEight() {
    #expect(SpaceIndicatorView.tileGrid(1) == (1, 1))
    #expect(SpaceIndicatorView.tileGrid(5) == (5, 1))
    #expect(SpaceIndicatorView.tileGrid(8) == (8, 1))
    #expect(SpaceIndicatorView.tileGrid(9) == (5, 2))
    #expect(SpaceIndicatorView.tileGrid(16) == (8, 2))
    #expect(SpaceIndicatorView.tileGrid(17) == (6, 3))
    #expect(IndicatorStyle.tiles.size(total: 5) == NSSize(width: 196, height: 40))
    #expect(IndicatorStyle.dots.size(total: 5) == NSSize(width: 128, height: 44))
    #expect(IndicatorStyle.dots.size(total: 12).width > 128)
  }
}
