import AppKit
import StatisticsModel

@MainActor
final class StatisticsViewController: NSViewController {
  private let savedTimeLabel = SettingsDesign.text("0 s", size: 31, weight: .semibold)
  private let totalActionsLabel = SettingsDesign.text("0", size: 25, weight: .semibold)
  private let trackingSinceLabel = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)
  private let recordingSwitch = NSSwitch()
  private let explanationButton = NSButton(title: "How it's calculated", target: nil, action: nil)
  private let explanationText = SettingsDesign.text(
    "Time saved = actions × (native duration − accelerated duration), calculated " +
      "separately for each action and speed. Reference durations in seconds " +
      "(native / Fast / Faster / Instant): Space and ⌘ Tab 0.68 / 0.05 / 0.03 / 0.03; " +
      "Mission Control 0.355 / 0.085 / 0.125 / 0.065; App Exposé " +
      "0.30 / 0.13 / 0.125 / 0.03. Left/right and opening/closing are averaged. " +
      "The combined overview gesture uses the average of Mission Control and App Exposé. " +
      "The former Fastest preset uses Faster values. Measurements come from one local " +
      "screen recording; other Macs, macOS versions and Reduce Motion may differ. " +
      "Counts and settings stay on this Mac.",
    size: 12, color: .secondaryLabelColor)
  private var countLabels: [NSTextField] = []
  private var timeLabels: [NSTextField] = []
  private var speedCountLabels: [StatisticsSpeed: NSTextField] = [:]
  private var speedTimeLabels: [StatisticsSpeed: NSTextField] = [:]
  private var activationObserver: NSObjectProtocol?
  private var previewSummary: StatisticsSummary?
  private var isPreview: Bool {
    Bundle.main.object(forInfoDictionaryKey: "MacceleratePreview") as? Bool == true
  }

  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()

    savedTimeLabel.font = .monospacedDigitSystemFont(ofSize: 31, weight: .semibold)
    totalActionsLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .semibold)
    let intro = SettingsDesign.heading("Your time, back.",
                                       subtitle: "A local count of the transitions Maccelerate speeds up.")

    let savedColumn = SettingsDesign.stack([
      SettingsDesign.text("ESTIMATED TIME SAVED", size: 10, weight: .semibold,
                          color: .secondaryLabelColor),
      savedTimeLabel,
    ], spacing: 8)
    let actionsColumn = SettingsDesign.stack([
      SettingsDesign.text("ACCELERATED ACTIONS", size: 10, weight: .semibold,
                          color: .secondaryLabelColor),
      totalActionsLabel,
    ], spacing: 8)
    savedColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
    actionsColumn.setContentHuggingPriority(.required, for: .horizontal)
    let hero = SettingsDesign.stack([savedColumn, NSView(), actionsColumn], vertical: false, spacing: 20)
    hero.heightAnchor.constraint(equalToConstant: 94).isActive = true
    let summaryCard = SettingsDesign.card([hero], padding: 20)
    summaryCard.heightAnchor.constraint(equalToConstant: 134).isActive = true

    var rows: [NSView] = []
    for category in StatisticsCategory.allCases {
      let countLabel = SettingsDesign.text("0", size: 15, weight: .semibold)
      countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
      let timeLabel = SettingsDesign.text("0 s estimated", size: 11, color: .secondaryLabelColor)
      countLabels.append(countLabel)
      timeLabels.append(timeLabel)
      let value = SettingsDesign.stack([countLabel, timeLabel], spacing: 3)
      value.alignment = .trailing
      value.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
      rows.append(SettingsDesign.row(category.title, detail: category.detail,
                                     symbol: category.symbol, control: value, height: 62))
    }
    let activityCard = SettingsDesign.card(rows, padding: 12)
    var speedRows: [NSView] = []
    for speed in [StatisticsSpeed.fast, .faster, .instant] {
      let countLabel = SettingsDesign.text("0", size: 15, weight: .semibold)
      countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
      let timeLabel = SettingsDesign.text("0 s estimated", size: 11,
                                          color: .secondaryLabelColor)
      speedCountLabels[speed] = countLabel
      speedTimeLabels[speed] = timeLabel
      let value = SettingsDesign.stack([countLabel, timeLabel], spacing: 3)
      value.alignment = .trailing
      value.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
      let detail = speed == .faster ? "Includes the former Fastest preset" : "Recorded at this speed"
      let row = SettingsDesign.row(speed.title, detail: detail,
                                   symbol: "speedometer", control: value, height: 62)
      speedRows.append(row)
    }
    let speedCard = SettingsDesign.card(speedRows, padding: 12)
    let estimateNote = SettingsDesign.text(
      "Estimate from one 60 fps screen recording. Results vary by Mac and macOS.",
      size: 11, color: .secondaryLabelColor)

    recordingSwitch.target = self
    recordingSwitch.action = #selector(recordingChanged)
    recordingSwitch.setAccessibilityLabel("Record local statistics")
    let recordingCard = SettingsDesign.card([
      SettingsDesign.row("Record local statistics",
                         detail: "Pause counting without losing previous results.",
                         symbol: "chart.bar.xaxis", control: recordingSwitch),
    ], padding: 12)

    explanationButton.isBordered = false
    explanationButton.imagePosition = .imageLeading
    explanationButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    explanationButton.target = self
    explanationButton.action = #selector(toggleExplanation)
    explanationButton.setAccessibilityLabel("How estimated time saved is calculated")
    explanationText.isHidden = true
    let explanation = SettingsDesign.stack([explanationButton, explanationText], spacing: 8)
    explanation.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
    let explanationCard = SettingsDesign.card([explanation], padding: 16)

    let resetButton = SettingsDesign.button("Reset statistics…", target: self,
                                            action: #selector(confirmReset))
    resetButton.setAccessibilityLabel("Reset statistics")
    let resetRow = SettingsDesign.stack([
      trackingSinceLabel, NSView(), resetButton,
    ], vertical: false, spacing: 12)
    let content = SettingsDesign.stack([
      intro, summaryCard, SettingsDesign.section("By action", content: activityCard),
      SettingsDesign.section("By speed", content: speedCard),
      estimateNote,
      SettingsDesign.section("Local statistics", content: recordingCard),
      explanationCard, resetRow,
    ], spacing: 18)
    SettingsDesign.page(content, in: view)
    refresh()

    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.refresh() }
    }
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    refresh()
  }

  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
  }

  private func refresh() {
    let summary: StatisticsSummary
    if isPreview {
      if previewSummary == nil {
        let large = CommandLine.arguments.contains("--preview-stats-large")
          || Bundle.main.object(forInfoDictionaryKey: "MacceleratePreviewStatsLarge") as? Bool == true
        var preview = StatisticsAccumulator()
        if large {
          for (action, count) in [54_321, 4_321, 11_223, 9_876, 5_432].enumerated() {
            preview.add(action: action, speed: action % 2 == 0 ? 0 : 1,
                        count: UInt64(count))
          }
        }
        previewSummary = preview.summary(
          startedAt: large ? Date().addingTimeInterval(-86_400 * 120) : Date(),
          enabled: true)
      }
      summary = previewSummary!
    } else {
      summary = StatisticsStore.shared.summary()
    }

    savedTimeLabel.stringValue = StatisticsEstimate.formattedTime(for: summary.totalSeconds)
    totalActionsLabel.stringValue = Self.formattedCount(summary.totalCount)
    recordingSwitch.state = summary.enabled ? .on : .off
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    trackingSinceLabel.stringValue = "Tracking since \(formatter.string(from: summary.startedAt))"
    for category in StatisticsCategory.allCases {
      let count = summary.counts[category.rawValue]
      countLabels[category.rawValue].stringValue = Self.formattedCount(count)
      timeLabels[category.rawValue].stringValue =
        "\(StatisticsEstimate.formattedTime(for: summary.secondsByCategory[category.rawValue])) estimated"
    }
    for speed in [StatisticsSpeed.fast, .faster, .instant] {
      let index = speed.rawValue
      let legacyCount = speed == .faster ? summary.countsBySpeed[StatisticsSpeed.legacyFastest.rawValue] : 0
      let legacySeconds = speed == .faster ? summary.secondsBySpeed[StatisticsSpeed.legacyFastest.rawValue] : 0
      let (speedCount, overflow) = summary.countsBySpeed[index].addingReportingOverflow(legacyCount)
      speedCountLabels[speed]?.stringValue = Self.formattedCount(overflow ? UInt64.max : speedCount)
      speedTimeLabels[speed]?.stringValue =
        "\(StatisticsEstimate.formattedTime(for: summary.secondsBySpeed[index] + legacySeconds)) estimated"
    }
  }

  private static func formattedCount(_ count: UInt64) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
  }

  @objc private func recordingChanged(_ sender: NSSwitch) {
    if isPreview, let current = previewSummary {
      previewSummary = StatisticsSummary(startedAt: current.startedAt,
                                         enabled: sender.state == .on, counts: current.counts,
                                         secondsByCategory: current.secondsByCategory,
                                         countsBySpeed: current.countsBySpeed,
                                         secondsBySpeed: current.secondsBySpeed)
    } else {
      StatisticsStore.shared.setEnabled(sender.state == .on)
    }
    refresh()
  }

  @objc private func toggleExplanation() {
    explanationText.isHidden.toggle()
    explanationButton.image = NSImage(systemSymbolName: explanationText.isHidden
      ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
  }

  @objc private func confirmReset() {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Reset local statistics?"
    alert.informativeText = "All recorded counts and the tracking start date will be cleared."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Reset Statistics")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertSecondButtonReturn else { return }
      Task { @MainActor [weak self] in
        if self?.isPreview == true, let current = self?.previewSummary {
          self?.previewSummary = StatisticsAccumulator().summary(startedAt: Date(),
                                                                  enabled: current.enabled)
        } else {
          StatisticsStore.shared.reset()
        }
        self?.refresh()
      }
    }
  }
}
