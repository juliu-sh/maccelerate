import AppKit

@MainActor
final class AppearanceSettingsViewController: NSViewController {
  private let indicator = SpaceIndicator.shared
  private let enabledSwitch = SettingsSwitch(label: "Show the Space indicator")
  private let options = IndicatorStyle.allCases.map { IndicatorStyleOption(style: $0) }
  private let position = IndicatorPositionPicker()
  private lazy var shadow = SettingsSegmented(titles: IndicatorShadow.allCases.map(\.title),
                                              selected: indicator.shadow.rawValue, size: .compact,
                                              label: "Indicator shadow")
  private lazy var shape = SettingsSegmented(titles: IndicatorShadowShape.allCases.map(\.title),
                                             selected: indicator.shadowShape.rawValue, size: .compact,
                                             label: "Indicator shadow shape")
  private lazy var duration = SettingsSegmented(titles: IndicatorSettings.durations.map { "\($0) ms" },
                                                selected: 0, size: .compact, label: "Display duration")
  private var gate: SettingsGate?

  override func loadView() { view = NSView() }

  private static func column(_ groups: [(title: String, control: NSView)]) -> NSView {
    let stack = SettingsDesign.stack(spacing: 6)
    stack.distribution = .fill
    for group in groups {
      stack.addArrangedSubview(SettingsDesign.text(group.title, color: SettingsStyle.label))
      stack.addArrangedSubview(group.control)
      group.control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      stack.setCustomSpacing(12, after: group.control)
    }
    return stack
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    position.onSelect = { [weak self] in self?.indicator.preview(seconds: 1.5) }
    for option in options {
      option.onSelect = { [weak self] style in
        self?.indicator.style = style
        self?.loadSettings()
      }
    }
    let grid = SettingsDesign.stack([SettingsStyle.columns(Array(options[0...1])),
                                     SettingsStyle.columns(Array(options[2...3]))], spacing: 12)
    for row in grid.arrangedSubviews { row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }

    shadow.onChange = { [weak self] index in
      self?.indicator.shadow = IndicatorShadow.allCases[index]
      self?.shadowChanged()
    }
    shape.onChange = { [weak self] index in
      self?.indicator.shadowShape = IndicatorShadowShape.allCases[index]
      self?.shadowChanged()
    }
    duration.onChange = { [weak self] in self?.indicator.durationMs = IndicatorSettings.durations[$0] }
    let preview = SettingsStyle.row("Try it on your screen",
                                    control: SettingsButton("Preview") { [weak self] in self?.indicator.preview() })

    let card = SettingsCard(title: "Space indicator", accessory: enabledSwitch)
    let body = SettingsDesign.stack(spacing: 0)
    func add(_ view: NSView, spacingAfter: CGFloat = 0) {
      body.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
      body.setCustomSpacing(spacingAfter, after: view)
    }
    add(grid, spacingAfter: 12)
    add(card.divider(), spacingAfter: 12)
    let screen = Self.column([("Position", position)])
    let controls = Self.column([("Shadow", shadow), ("Shadow shape", shape), ("Display duration", duration)])
    let row = SettingsDesign.stack([screen, controls], vertical: false, spacing: 16)
    row.alignment = .top
    row.distribution = .fill
    add(row)
    // The screen ends level with the last control, at about 4:3.
    screen.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.44).isActive = true
    screen.heightAnchor.constraint(equalTo: controls.heightAnchor).isActive = true

    let gate = SettingsGate(body)
    self.gate = gate
    enabledSwitch.onChange = { [weak self] isOn in
      self?.indicator.isOn = isOn
      self?.gate?.isOpen = isOn
    }
    card.add(gate, spacingAfter: 14)
    // Outside the gate: a style can be tried before the indicator is turned on.
    card.add(card.divider())
    card.add(preview)
    let note = SettingsDesign.text("Follows your Mac’s appearance and accessibility preferences.",
                                   size: 11, color: SettingsStyle.secondary)
    SettingsDesign.page(SettingsDesign.stack([card, note], spacing: 12), in: view)
    loadSettings()
  }

  override func viewWillAppear() { super.viewWillAppear(); loadSettings() }

  private func shadowChanged() {
    loadSettings()
    // Longer than a real switch: a shadow can only be judged on the actual wallpaper.
    indicator.preview(seconds: 1.5)
  }

  private func loadSettings() {
    enabledSwitch.isOn = indicator.isOn
    gate?.isOpen = indicator.isOn
    for option in options {
      option.isSelected = option.style == indicator.style
      option.setShadow(indicator.shadow, shape: indicator.shadowShape)
    }
    shadow.selected = indicator.shadow.rawValue
    shape.selected = indicator.shadowShape.rawValue
    shape.isEnabled = indicator.shadow != .none
    duration.selected = IndicatorSettings.durations.firstIndex(of: indicator.durationMs) ?? 0
    position.needsDisplay = true
  }
}
