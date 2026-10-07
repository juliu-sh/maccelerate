import AppKit
import ISS
import StatisticsModel

private struct StatisticsArchive: Codable {
  var startedAt: Date
  var enabled: Bool
  var buckets: [String: UInt64]
}

@MainActor
final class StatisticsStore {
  static let shared = StatisticsStore()

  var didFlush: ((StatisticsSummary) -> Void)?

  private let defaults: UserDefaults
  private let archiveKey = "localStatisticsV1"
  private let osVersion: String
  private var archive: StatisticsArchive
  private var archiveNeedsInitialization: Bool
  private var pendingFlush: DispatchWorkItem?
  private var motionObserver: NSObjectProtocol?
  private var sleepObserver: NSObjectProtocol?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let version = ProcessInfo.processInfo.operatingSystemVersion
    osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    if let data = defaults.data(forKey: archiveKey),
      let saved = try? JSONDecoder().decode(StatisticsArchive.self, from: data) {
      archive = saved
      archiveNeedsInitialization = false
    } else {
      archive = StatisticsArchive(startedAt: Date(), enabled: true, buckets: [:])
      archiveNeedsInitialization = true
    }
  }

  func start() {
    // The first launch establishes the beginning of tracking, even if the tab is never opened.
    if archiveNeedsInitialization {
      persist()
      archiveNeedsInitialization = false
    }
    iss_statistics_set_reduce_motion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    iss_statistics_set_dirty_callback {
      DispatchQueue.main.async { StatisticsStore.shared.scheduleFlushIfNeeded() }
    }
    iss_statistics_set_enabled(archive.enabled)
    motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.flush()
        iss_statistics_set_reduce_motion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
      }
    }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.flush() }
    }
  }

  func stop() {
    didFlush = nil
    flush()
    iss_statistics_set_enabled(false)
    iss_statistics_set_dirty_callback(nil)
    if let motionObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(motionObserver)
      self.motionObserver = nil
    }
    if let sleepObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
      self.sleepObserver = nil
    }
  }

  func summary() -> StatisticsSummary {
    var accumulator = StatisticsAccumulator()
    for (key, count) in archive.buckets {
      let parts = key.split(separator: "|")
      guard parts.count == 4, let action = Int(parts[1]),
        let speed = Int(parts[2]) else { continue }
      accumulator.add(action: action, speed: speed, count: count)
    }
    var pending = ISSStatisticsSnapshot()
    iss_statistics_copy_snapshot(&pending)
    forEachCount(in: pending) { action, speed, _, count in
      accumulator.add(action: action, speed: speed, count: count)
    }
    return accumulator.summary(startedAt: archive.startedAt, enabled: archive.enabled)
  }

  func setEnabled(_ enabled: Bool) {
    guard archive.enabled != enabled else { return }
    archive.enabled = enabled
    flush()
    iss_statistics_set_enabled(enabled)
    persist()
  }

  func reset() {
    pendingFlush?.cancel()
    pendingFlush = nil
    iss_statistics_reset()
    archive.buckets.removeAll()
    archive.startedAt = Date()
    persist()
  }

  func flush() {
    pendingFlush?.cancel()
    pendingFlush = nil
    var pending = ISSStatisticsSnapshot()
    iss_statistics_take_snapshot(&pending)
    var changed = false
    forEachCount(in: pending) { action, speed, reduced, count in
      let key = "\(osVersion)|\(action)|\(speed)|\(reduced)"
      archive.buckets[key] = adding(count, to: archive.buckets[key] ?? 0)
      changed = true
    }
    if changed { persist() }
    didFlush?(summary())
  }

  private func scheduleFlushIfNeeded() {
    guard pendingFlush == nil else { return }
    var pending = ISSStatisticsSnapshot()
    iss_statistics_copy_snapshot(&pending)
    guard snapshotHasCounts(pending) else { return }
    let work = DispatchWorkItem { [weak self] in self?.flush() }
    pendingFlush = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(archive) else { return }
    defaults.set(data, forKey: archiveKey)
  }

  private func forEachCount(
    in snapshot: ISSStatisticsSnapshot,
    _ body: (Int, Int, Int, UInt64) -> Void
  ) {
    withUnsafeBytes(of: snapshot.counts) { bytes in
      let values = bytes.bindMemory(to: UInt64.self)
      for (index, count) in values.enumerated() where count > 0 {
        body(index / 8, (index / 2) % 4, index % 2, count)
      }
    }
  }

  private func snapshotHasCounts(_ snapshot: ISSStatisticsSnapshot) -> Bool {
    withUnsafeBytes(of: snapshot.counts) { bytes in
      bytes.bindMemory(to: UInt64.self).contains { $0 > 0 }
    }
  }

  private func adding(_ count: UInt64, to existing: UInt64) -> UInt64 {
    let (sum, overflow) = existing.addingReportingOverflow(count)
    return overflow ? UInt64.max : sum
  }
}
