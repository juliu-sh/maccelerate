import Foundation

// Raw values match the ISS snapshot and existing localStatisticsV1 archives.
public enum StatisticsCategory: Int, CaseIterable {
  case spaceSwitch, appSwitch, missionControl, appExpose, overviewGesture

  public var title: String {
    switch self {
    case .spaceSwitch: return "Space switches"
    case .appSwitch: return "App switching"
    case .missionControl: return "Mission Control"
    case .appExpose: return "App Exposé"
    case .overviewGesture: return "Overview gestures"
    }
  }

  public var detail: String {
    switch self {
    case .spaceSwitch: return "Shortcuts, menu and horizontal trackpad swipes"
    case .appSwitch: return "⌘ Tab to an app on another Space"
    case .missionControl: return "Shortcuts and menu actions"
    case .appExpose: return "Shortcuts and menu actions"
    case .overviewGesture: return "Mission Control and App Exposé via trackpad"
    }
  }

  public var symbol: String {
    switch self {
    case .spaceSwitch: return "rectangle.2.swap"
    case .appSwitch: return "square.on.square"
    case .missionControl: return "rectangle.3.group"
    case .appExpose: return "rectangle.stack"
    case .overviewGesture: return "hand.draw"
    }
  }
}

public enum StatisticsSpeed: Int, CaseIterable {
  case fast, faster, legacyFastest, instant

  public var title: String {
    switch self {
    case .fast: return "Fast"
    case .faster: return "Faster"
    case .legacyFastest: return "Fastest (legacy)"
    case .instant: return "Instant"
    }
  }
}

public struct StatisticsSummary {
  public let startedAt: Date
  public let enabled: Bool
  public let counts: [UInt64]
  public let secondsByCategory: [Double]
  public let countsBySpeed: [UInt64]
  public let secondsBySpeed: [Double]

  public init(startedAt: Date, enabled: Bool, counts: [UInt64],
              secondsByCategory: [Double], countsBySpeed: [UInt64],
              secondsBySpeed: [Double]) {
    self.startedAt = startedAt
    self.enabled = enabled
    self.counts = counts
    self.secondsByCategory = secondsByCategory
    self.countsBySpeed = countsBySpeed
    self.secondsBySpeed = secondsBySpeed
  }

  public var totalCount: UInt64 {
    counts.reduce(0) { total, count in
      let (sum, overflow) = total.addingReportingOverflow(count)
      return overflow ? UInt64.max : sum
    }
  }
  public var totalSeconds: Double { secondsByCategory.reduce(0, +) }
}

public struct StatisticsAccumulator {
  private var counts = Array(repeating: UInt64(0), count: StatisticsCategory.allCases.count)
  private var seconds = Array(repeating: 0.0, count: StatisticsCategory.allCases.count)
  private var speedCounts = Array(repeating: UInt64(0), count: StatisticsSpeed.allCases.count)
  private var speedSeconds = Array(repeating: 0.0, count: StatisticsSpeed.allCases.count)

  public init() {}

  public mutating func add(action: Int, speed: Int, count: UInt64) {
    guard let category = StatisticsCategory(rawValue: action),
      let preset = StatisticsSpeed(rawValue: speed), count > 0 else { return }
    let estimate = StatisticsEstimate.secondsSaved(for: category,
                                                   speed: preset) * Double(count)
    let index = category.rawValue
    counts[index] = saturatingAdd(counts[index], count)
    seconds[index] += estimate
    speedCounts[speed] = saturatingAdd(speedCounts[speed], count)
    speedSeconds[speed] += estimate
  }

  public func summary(startedAt: Date, enabled: Bool) -> StatisticsSummary {
    StatisticsSummary(startedAt: startedAt, enabled: enabled, counts: counts,
                      secondsByCategory: seconds, countsBySpeed: speedCounts,
                      secondsBySpeed: speedSeconds)
  }

  private func saturatingAdd(_ a: UInt64, _ b: UInt64) -> UInt64 {
    let (sum, overflow) = a.addingReportingOverflow(b)
    return overflow ? UInt64.max : sum
  }
}

public enum StatisticsEstimate {
  // Visible transition durations (seconds) from one 60 fps screen recording.
  // Opening/closing and left/right are averaged because existing archives do
  // not identify direction. Fastest is a removed preset, approximated by Faster.
  // The same baseline is a fallback for other macOS builds and Reduce Motion.
  private static let native = [0.68, 0.68, 0.355, 0.30]
  private static let accelerated: [[Double]] = [
    [0.05, 0.03, 0.03],     // Space (Fast, Faster, Instant)
    [0.05, 0.03, 0.03],     // Cmd-Tab uses the Space switch measurement
    [0.085, 0.125, 0.065], // Mission Control
    [0.13, 0.125, 0.03],   // App Exposé
  ]

  public static func secondsSaved(for category: StatisticsCategory,
                                  speed: StatisticsSpeed) -> Double {
    if category == .overviewGesture {
      // The recorded vertical gesture bucket combines both overview modes.
      return (secondsSaved(for: .missionControl, speed: speed)
              + secondsSaved(for: .appExpose, speed: speed)) / 2
    }
    let speedIndex: Int
    switch speed {
    case .fast: speedIndex = 0
    case .faster, .legacyFastest: speedIndex = 1
    case .instant: speedIndex = 2
    }
    let index = category.rawValue
    return max(0, native[index] - accelerated[index][speedIndex])
  }

  public static func formattedTime(for seconds: Double) -> String {
    if seconds < 1 { return seconds <= 0 ? "0 s" : "<1 s" }
    let rounded = seconds.rounded()
    let wholeSeconds = rounded >= Double(Int.max) ? Int.max : Int(rounded)
    if wholeSeconds < 60 { return "\(wholeSeconds) s" }
    let minutes = wholeSeconds / 60
    let remainder = wholeSeconds % 60
    if minutes < 60 { return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s" }
    let hours = minutes / 60
    let leftoverMinutes = minutes % 60
    return leftoverMinutes == 0 ? "\(hours) h" : "\(hours) h \(leftoverMinutes) min"
  }
}
