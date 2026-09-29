enum SwitchingSpeedPreset: Int, CaseIterable {
  case fast
  case faster
  case instant

  var title: String {
    switch self {
    case .fast: return "Fast"
    case .faster: return "Faster"
    case .instant: return "Instant"
    }
  }

  var velocity: Double {
    switch self {
    case .fast: return 100
    case .faster: return 400
    case .instant: return 1000
    }
  }

  var boostCount: Int { rawValue + 1 }

  static func fromStoredVelocity(_ value: Double) -> Self {
    // 50, 60, 80 and 2000 were used by older releases. The removed Normal
    // and Fastest settings now resolve to the closest available preset.
    if value == 80 { return .instant }
    if value == 60 { return .faster }
    if value > 0 && value <= 100 { return .fast }
    if value <= 400 && value > 100 { return .faster }
    return .instant
  }
}
