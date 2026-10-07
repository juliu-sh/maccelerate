import Foundation
import Testing
import StatisticsModel

@Suite("Measured statistics estimates")
struct StatisticsModelTests {
  @Test func measuredSavingsAndCmdTabUsesSpaceReference() {
    #expect(abs(StatisticsEstimate.secondsSaved(for: .spaceSwitch, speed: .fast) - 0.63) < 0.000_001)
    #expect(abs(StatisticsEstimate.secondsSaved(for: .spaceSwitch, speed: .faster) - 0.65) < 0.000_001)
    #expect(abs(StatisticsEstimate.secondsSaved(for: .spaceSwitch, speed: .instant) - 0.65) < 0.000_001)
    for speed in StatisticsSpeed.allCases {
      #expect(StatisticsEstimate.secondsSaved(for: .appSwitch, speed: speed)
              == StatisticsEstimate.secondsSaved(for: .spaceSwitch, speed: speed))
    }
    #expect(abs(StatisticsEstimate.secondsSaved(for: .missionControl, speed: .fast) - 0.27) < 0.000_001)
    #expect(abs(StatisticsEstimate.secondsSaved(for: .appExpose, speed: .instant) - 0.27) < 0.000_001)
    #expect(StatisticsEstimate.secondsSaved(for: .missionControl, speed: .legacyFastest)
            == StatisticsEstimate.secondsSaved(for: .missionControl, speed: .faster))
  }

  @Test func aggregatesEveryBucketUsingItsOwnSpeed() {
    var accumulator = StatisticsAccumulator()
    accumulator.add(action: 0, speed: 0, count: 100) // 63 s
    accumulator.add(action: 1, speed: 1, count: 100) // 65 s
    accumulator.add(action: 2, speed: 0, count: 10)  // 2.7 s
    accumulator.add(action: 3, speed: 3, count: 10)  // 2.7 s
    accumulator.add(action: 4, speed: 3, count: 10)  // 2.8 s
    let summary = accumulator.summary(startedAt: .distantPast, enabled: true)
    #expect(summary.totalCount == 230)
    #expect(abs(summary.totalSeconds - 136.2) < 0.000_001)
    #expect(summary.countsBySpeed == [110, 100, 0, 20])
    #expect(abs(summary.secondsBySpeed.reduce(0, +) - summary.totalSeconds) < 0.000_001)
    #expect(StatisticsEstimate.formattedTime(for: summary.totalSeconds) == "2 min 16 s")
  }

  @Test func ignoresUnknownBucketsAndKeepsEmptyState() {
    var accumulator = StatisticsAccumulator()
    accumulator.add(action: 42, speed: 0, count: 10)
    accumulator.add(action: 0, speed: 42, count: 10)
    let empty = accumulator.summary(startedAt: .distantPast, enabled: false)
    #expect(empty.totalCount == 0)
    #expect(empty.totalSeconds == 0)
    #expect(StatisticsEstimate.formattedTime(for: empty.totalSeconds) == "0 s")
    accumulator.add(action: 0, speed: 0, count: 1)
    let one = accumulator.summary(startedAt: .distantPast, enabled: false)
    #expect(one.totalCount == 1)
    #expect(StatisticsEstimate.formattedTime(for: one.totalSeconds) == "<1 s")
  }

  @Test func largeHistoricCountsRemainFiniteAndDoNotOverflowTheFormatter() {
    var accumulator = StatisticsAccumulator()
    accumulator.add(action: 0, speed: 0, count: UInt64.max)
    let summary = accumulator.summary(startedAt: .distantPast, enabled: true)
    #expect(summary.totalCount == UInt64.max)
    #expect(summary.totalSeconds.isFinite)
    #expect(!StatisticsEstimate.formattedTime(for: summary.totalSeconds).isEmpty)
  }
}
