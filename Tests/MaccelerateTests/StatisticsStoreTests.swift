import Foundation
import ISS
import StatisticsModel
import Testing
@testable import Maccelerate

@Suite(.serialized)
@MainActor
struct StatisticsStoreTests {
  private struct Saved: Encodable {
    let startedAt: Date
    let enabled: Bool
    let buckets: [String: UInt64]
  }

  @Test func restoresTotalsAndPersistsPauseAndReset() throws {
    let name = "MaccelerateStatisticsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    iss_statistics_reset()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let saved = Saved(startedAt: start, enabled: true,
                      buckets: ["26.0.0|0|0|0": 3, "27.0.1|1|3|1": 2,
                                "invalid": 999, "27.0.1|99|3|0": 999])
    defaults.set(try JSONEncoder().encode(saved), forKey: "localStatisticsV1")
    let store = StatisticsStore(defaults: defaults)
    #expect(store.summary().totalCount == 5)
    #expect(store.summary().startedAt == start)
    #expect(store.summary().counts[StatisticsCategory.spaceSwitch.rawValue] == 3)
    store.setEnabled(false)
    let paused = StatisticsStore(defaults: defaults)
    #expect(!paused.summary().enabled)
    #expect(paused.summary().totalCount == 5)
    paused.reset()
    let reset = StatisticsStore(defaults: defaults)
    #expect(reset.summary().totalCount == 0)
    #expect(!reset.summary().enabled)
    #expect(reset.summary().startedAt > start)
  }

  @Test func corruptedArchiveStartsEmpty() throws {
    let name = "MaccelerateStatisticsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    iss_statistics_reset()
    defaults.set(Data("broken archive".utf8), forKey: "localStatisticsV1")
    let summary = StatisticsStore(defaults: defaults).summary()
    #expect(summary.totalCount == 0)
    #expect(summary.enabled)
  }
}
