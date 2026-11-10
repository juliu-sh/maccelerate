import AppKit
import StatisticsModel

/// One fill on a tinted track; bars in a list share the same zero and the same scale.
final class SettingsMeter: StyledLayerView {
  private let fill = CALayer()
  private let fraction: Double

  init(fraction: Double) {
    self.fraction = fraction
    super.init(frame: .zero)
    layer?.addSublayer(fill)
    heightAnchor.constraint(equalToConstant: 6).isActive = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func applyStyle() {
    styled {
      layer?.backgroundColor = SettingsStyle.track.cgColor
      layer?.cornerRadius = 3
      fill.backgroundColor = SettingsStyle.switchOn.cgColor
      fill.cornerRadius = 3
      // A tiny count stays visible; zero stays empty.
      let width = fraction > 0 ? max(6, bounds.width * fraction) : 0
      fill.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
    }
  }
}

/// Share of actions per speed: one hue, light to dark, with a 2 pt surface gap.
final class SettingsShareBar: StyledLayerView {
  private let parts: [(share: Double, color: NSColor)]
  private let fills: [CALayer]

  init(parts: [(share: Double, color: NSColor)]) {
    self.parts = parts
    fills = parts.map { _ in CALayer() }
    super.init(frame: .zero)
    fills.forEach { layer?.addSublayer($0) }
    heightAnchor.constraint(equalToConstant: 10).isActive = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func applyStyle() {
    styled {
      layer?.masksToBounds = true
      layer?.cornerRadius = 4
      let visible = parts.filter { $0.share > 0 }.count
      layer?.backgroundColor = visible == 0 ? SettingsStyle.track.cgColor : NSColor.clear.cgColor
      let available = bounds.width - CGFloat(max(visible - 1, 0)) * 2
      var x: CGFloat = 0
      for (part, fill) in zip(parts, fills) {
        let width = available * part.share
        fill.backgroundColor = part.color.cgColor
        fill.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
        if width > 0 { x += width + 2 }
      }
    }
  }
}
@MainActor
final class StatisticsViewController: NSViewController {
  private static let explanation =
    "Time saved = actions × (native duration − accelerated duration), calculated " +
    "separately for each action and speed. Reference durations in seconds " +
    "(native / Fast / Faster / Instant): Space and ⌘ Tab 0.68 / 0.05 / 0.03 / 0.03; " +
    "Mission Control 0.355 / 0.085 / 0.125 / 0.065; App Exposé " +
    "0.30 / 0.13 / 0.125 / 0.03. Left/right and opening/closing are averaged. " +
    "The combined overview gesture uses the average of Mission Control and App Exposé. " +
    "The former Fastest preset uses Faster values. Measurements come from one local " +
    "screen recording; other Macs, macOS versions and Reduce Motion may differ. " +
    "Counts and settings stay on this Mac."

  private let content = SettingsDesign.stack(spacing: SettingsStyle.cardGap)
  private let recordingSwitch = SettingsSwitch(label: "Record local statistics")
  private let explanationText = SettingsDesign.text(explanation, size: 11, color: SettingsStyle.secondary)
  private lazy var disclosure = SettingsIconButton(symbol: "chevron.right", label: "How it’s calculated") {
    [weak self] in self?.toggleExplanation()
  }
  private lazy var local = localCard()
  private var activationObserver: NSObjectProtocol?
  private var previewSummary: StatisticsSummary?
  private var isPreview: Bool {
    Bundle.main.object(forInfoDictionaryKey: "MacceleratePreview") as? Bool == true
  }

  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    recordingSwitch.onChange = { [weak self] in self?.recordingChanged($0) }
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

  private func summary() -> StatisticsSummary {
    guard isPreview else { return StatisticsStore.shared.summary() }
    if let previewSummary { return previewSummary }
    var sample = StatisticsAccumulator()
    let large = CommandLine.arguments.contains("--preview-stats-large")
      || Bundle.main.object(forInfoDictionaryKey: "MacceleratePreviewStatsLarge") as? Bool == true
    if large {
      for (action, count) in [54_321, 4_321, 11_223, 9_876, 5_432].enumerated() {
        sample.add(action: action, speed: action % 2 == 0 ? 0 : 1, count: UInt64(count))
      }
    }
    let summary = sample.summary(startedAt: large ? Date().addingTimeInterval(-86_400 * 120) : Date(),
                                 enabled: true)
    previewSummary = summary
    return summary
  }

  /// The figures change between visits, so the cards above the settings are rebuilt.
  private func refresh() {
    let summary = summary()
    recordingSwitch.isOn = summary.enabled
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for card in [Self.heroCard(summary, sample: isPreview), Self.actionsCard(summary), Self.speedCard(summary), local] {
      content.addArrangedSubview(card)
      card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
  }

  /// Counts stop at the largest value instead of overflowing.
  private static func saturatingSum(_ first: UInt64, _ second: UInt64) -> UInt64 {
    let (sum, overflow) = first.addingReportingOverflow(second)
    return overflow ? .max : sum
  }

  private static func count(_ value: UInt64) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
  }

  /// Digits carry the weight; units step back so the figure reads at a glance.
  private static func heroValue(_ text: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (index, token) in text.split(separator: " ").enumerated() {
      let isNumber = token.contains { $0.isNumber }
      if index > 0 { result.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 24)])) }
      result.append(NSAttributedString(string: String(token), attributes: [
        .font: NSFont.systemFont(ofSize: isNumber ? 48 : 24, weight: isNumber ? .semibold : .medium),
        .foregroundColor: isNumber ? SettingsStyle.label : SettingsStyle.secondary,
      ]))
    }
    return result
  }

  private static func heroCard(_ summary: StatisticsSummary, sample: Bool) -> NSView {
    let card = SettingsCard(title: "Estimated time saved", accessory: sample ? SettingsChip("Sample data") : nil)
    let figure = NSTextField(labelWithAttributedString: heroValue(
      StatisticsEstimate.formattedTime(for: summary.totalSeconds)))
    card.add(figure, spacingAfter: 12)
    let days = max(1, Date().timeIntervalSince(summary.startedAt) / 86_400)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    card.add(card.divider(), spacingAfter: 12)
    card.add(SettingsStyle.columns([
      SettingsStyle.metric("Accelerated actions", value: count(summary.totalCount)),
      SettingsStyle.metric("Saved per day",
                        value: StatisticsEstimate.formattedTime(for: summary.totalSeconds / days.rounded(.down))),
      SettingsStyle.metric("Tracking since", value: formatter.string(from: summary.startedAt)),
    ]))
    card.addGap(8)
    return card
  }

  /// Ranked by time saved, largest first, against one shared scale.
  private static func actionsCard(_ summary: StatisticsSummary) -> NSView {
    let card = SettingsCard(title: "Time saved by action")
    let ranked = StatisticsCategory.allCases.sorted {
      summary.secondsByCategory[$0.rawValue] > summary.secondsByCategory[$1.rawValue]
    }
    let largest = summary.secondsByCategory.max() ?? 0
    card.addRows(ranked.map { category in
      let seconds = summary.secondsByCategory[category.rawValue]
      let texts = SettingsDesign.stack([
        SettingsDesign.text(category.title, color: SettingsStyle.label),
        SettingsDesign.text("\(count(summary.counts[category.rawValue])) actions", size: 11,
                            color: SettingsStyle.secondary),
      ], spacing: 2)
      texts.widthAnchor.constraint(equalToConstant: 142).isActive = true
      let meter = SettingsMeter(fraction: largest > 0 ? seconds / largest : 0)
      let value = SettingsDesign.text(StatisticsEstimate.formattedTime(for: seconds), color: SettingsStyle.label)
      value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
      value.alignment = .right
      value.widthAnchor.constraint(equalToConstant: 86).isActive = true
      let row = SettingsDesign.stack([texts, meter, value], vertical: false, spacing: 12)
      row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
      row.toolTip = category.detail
      return row
    })
    return card
  }

  private static func speedCard(_ summary: StatisticsSummary) -> NSView {
    let card = SettingsCard(title: "Actions by speed")
    // The removed Fastest preset counts as Faster, as on the real page.
    let legacy = StatisticsSpeed.legacyFastest.rawValue
    let speeds = zip([StatisticsSpeed.fast, .faster, .instant], SettingsStyle.speedSteps).map { speed, color in
      let index = speed.rawValue
      let actions = saturatingSum(summary.countsBySpeed[index], speed == .faster ? summary.countsBySpeed[legacy] : 0)
      let seconds = summary.secondsBySpeed[index] + (speed == .faster ? summary.secondsBySpeed[legacy] : 0)
      return (title: speed.title, actions: actions, seconds: seconds, color: color)
    }
    let total = Double(speeds.reduce(UInt64(0)) { saturatingSum($0, $1.actions) })
    let bar = SettingsShareBar(parts: speeds.map { (total > 0 ? Double($0.actions) / total : 0, $0.color) })
    bar.toolTip = speeds.map { "\($0.title): \(count($0.actions))" }.joined(separator: " · ")
    card.add(bar, spacingAfter: 12)
    card.add(SettingsStyle.columns(speeds.map {
      SettingsStyle.metric($0.title, value: count($0.actions),
                        note: "\(StatisticsEstimate.formattedTime(for: $0.seconds)) saved", dot: $0.color)
    }))
    card.addGap(8)
    return card
  }

  private func localCard() -> NSView {
    let card = SettingsCard(title: "Local statistics")
    explanationText.isHidden = true
    card.addRows([
      SettingsStyle.row("Record local statistics", note: "Pause counting without losing previous results.",
                        control: recordingSwitch),
      SettingsStyle.row("How it’s calculated",
                        note: "Estimate from one 60 fps screen recording. Results vary by Mac and macOS.",
                        control: disclosure),
    ])
    card.add(explanationText, spacingAfter: 8)
    card.addRows([
      SettingsStyle.row("Reset statistics", note: "Clears all counts and the tracking start date.",
                        control: SettingsButton("Reset…") { [weak self] in self?.confirmReset() }),
    ])
    return card
  }

  private func toggleExplanation() {
    explanationText.isHidden.toggle()
    disclosure.symbol = explanationText.isHidden ? "chevron.right" : "chevron.down"
  }

  private func recordingChanged(_ isOn: Bool) {
    if isPreview, let current = previewSummary {
      previewSummary = StatisticsSummary(startedAt: current.startedAt, enabled: isOn, counts: current.counts,
                                         secondsByCategory: current.secondsByCategory,
                                         countsBySpeed: current.countsBySpeed,
                                         secondsBySpeed: current.secondsBySpeed)
    } else {
      StatisticsStore.shared.setEnabled(isOn)
    }
    refresh()
  }

  private func confirmReset() {
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
          self?.previewSummary = StatisticsAccumulator().summary(startedAt: Date(), enabled: current.enabled)
        } else {
          StatisticsStore.shared.reset()
        }
        self?.refresh()
      }
    }
  }
}
