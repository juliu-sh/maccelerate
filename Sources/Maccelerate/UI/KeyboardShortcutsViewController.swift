import AppKit
import Combine

private class RecordingView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func becomeFirstResponder() -> Bool { true }
}

final class KeyboardShortcutsViewController: NSViewController {
  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private let systemSwitch = SettingsSwitch(label: "Accelerate macOS shortcuts")
  private let systemSummary = SettingsDesign.text("", size: 11, color: SettingsStyle.secondary)
  private let additionalSwitch = SettingsSwitch(label: "Use additional shortcuts")
  private lazy var filter = SettingsSegmented(titles: ["Navigation", "Direct access"], selected: 0,
                                              label: "Shortcut category")
  private let statusLabel = SettingsDesign.text("Click a shortcut to record. Press Esc to cancel.", size: 11,
                                                color: SettingsStyle.secondary)
  /// Everything below the global switch; dimmed while additional shortcuts are off.
  private let additionalDetails = SettingsDesign.stack(spacing: 0)
  private lazy var additionalGate = SettingsGate(additionalDetails)
  private let shortcutRows = SettingsDesign.stack(spacing: 0)
  private let navigation: [HotkeyIdentifier] = [.left, .right, .lastSpace, .missionControl, .appExpose]

  private var shortcuts: [HotkeyIdentifier] = []

  override func loadView() {
    view = RecordingView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    SettingsDesign.page(SettingsDesign.stack([makeSystemCard(), makeAdditionalCard()],
                                             spacing: SettingsStyle.cardGap), in: view)
    loadShortcuts()
    // One rebuild per change, after the store has applied it.
    store.objectWillChange.receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in self?.loadSystemShortcuts() }
      .store(in: &cancellables)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    loadSystemShortcuts()
  }

  /// macOS's own shortcuts are edited in System Settings; Maccelerate only
  /// shows them and decides whether to accelerate them.
  private func makeSystemCard() -> NSView {
    let card = SettingsCard(title: "macOS shortcuts")
    systemSwitch.onChange = { isOn in
      UserDefaults.standard.set(isOn, forKey: SystemSpaceShortcuts.enabledKey)
      (NSApp.delegate as? AppDelegate)?.applySystemShortcuts()
    }
    let change = SettingsButton("Change…") {
      guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
      NSWorkspace.shared.open(url)
    }
    change.setAccessibilityLabel("Change in System Settings")
    card.addRows([
      SettingsStyle.row("Accelerate macOS shortcuts", noteLabel: systemSummary, control: systemSwitch),
      SettingsStyle.row("Set in System Settings", control: change),
    ])
    return card
  }

  private func makeAdditionalCard() -> NSView {
    let card = SettingsCard(title: "Additional shortcuts")
    additionalSwitch.onChange = { [weak self] isOn in
      ShortcutRecorderControl.cancelActiveRecording()
      self?.store.setAdditionalShortcutsEnabled(isOn)
    }
    card.addRows([SettingsStyle.row("Use additional shortcuts", note: "Your own key combinations, on top of macOS’s.",
                                    control: additionalSwitch)])

    filter.widthAnchor.constraint(equalToConstant: 244).isActive = true
    filter.onChange = { [weak self] _ in
      ShortcutRecorderControl.cancelActiveRecording()
      self?.loadShortcuts()
    }
    let reset = SettingsButton("Restore defaults…") { [weak self] in self?.resetAllShortcuts() }
    let controls = SettingsDesign.stack([filter, NSView(), reset], vertical: false, spacing: 12)
    statusLabel.setAccessibilityRole(.staticText)
    for view in [card.divider(), controls, shortcutRows, statusLabel] {
      additionalDetails.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: additionalDetails.widthAnchor).isActive = true
    }
    additionalDetails.setCustomSpacing(12, after: additionalDetails.arrangedSubviews[0])
    additionalDetails.setCustomSpacing(6, after: controls)
    additionalDetails.setCustomSpacing(6, after: shortcutRows)
    card.add(additionalGate)
    card.addGap(8)
    return card
  }

  private func loadSystemShortcuts() {
    systemSwitch.isOn = SystemSpaceShortcuts.isAccelerationEnabled
    systemSummary.stringValue = SystemSpaceShortcuts.summary(of: SystemSpaceShortcuts.current())
    (NSApp.delegate as? AppDelegate)?.applySystemShortcuts()
  }

  private func resetAllShortcuts() {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Restore all default shortcuts?"
    alert.informativeText = "This replaces your custom key combinations in both categories. Disabled shortcuts stay disabled."
    alert.addButton(withTitle: "Restore defaults")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      self?.store.resetToDefaults()
      self?.setStatus("Default shortcuts restored.")
    }
  }

  private func loadShortcuts() {
    additionalSwitch.isOn = store.additionalShortcutsEnabled
    additionalGate.isOpen = store.additionalShortcutsEnabled
    shortcuts = filter.selected == 0 ? navigation : HotkeyIdentifier.allCases.filter { !navigation.contains($0) }
    shortcutRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, identifier) in shortcuts.enumerated() {
      if index > 0 {
        let line = SettingsFill(SettingsStyle.divider)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        shortcutRows.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: shortcutRows.widthAnchor).isActive = true
      }
      let row = makeShortcutRow(identifier)
      shortcutRows.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: shortcutRows.widthAnchor).isActive = true
    }
    if let warning = store.conflictWarning { setStatus(warning, error: true) }
  }

  private func makeShortcutRow(_ identifier: HotkeyIdentifier) -> NSView {
    let isEnabled = store.isEnabled(identifier)
    let name = SettingsDesign.text(identifier.displayName, color: SettingsStyle.label)

    let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 124, height: 26))
    recorder.currentShortcut = store.combination(for: identifier)
    recorder.isEnabled = isEnabled
    recorder.setAccessibilityLabel("Shortcut for \(identifier.displayName)")
    recorder.onRecordingComplete = { [weak self] combination in
      self?.showResult(self?.store.update(combination, for: identifier) ?? .success(()),
                       success: "Shortcut saved for \(identifier.displayName).")
    }
    recorder.translatesAutoresizingMaskIntoConstraints = false

    let reset = SettingsIconButton(symbol: "arrow.counterclockwise",
                                   label: "Restore default for \(identifier.displayName)") { [weak self] in
      guard let self else { return }
      self.showResult(self.store.resetShortcut(for: identifier),
                      success: "Default shortcut restored for \(identifier.displayName).")
    }
    reset.isEnabled = isEnabled

    let toggle = SettingsSwitch(on: isEnabled, label: "Enable \(identifier.displayName)")
    toggle.onChange = { [weak self, weak toggle] isOn in
      guard let self, let toggle else { return }
      let result = self.store.setEnabled(isOn, for: identifier)
      toggle.isOn = self.store.isEnabled(identifier)
      self.showResult(result, success: "Shortcut \(self.store.isEnabled(identifier) ? "enabled" : "disabled").")
    }
    name.alphaValue = isEnabled ? 1 : SettingsStyle.dimmed

    let row = SettingsDesign.stack([name, NSView(), recorder, reset, toggle], vertical: false, spacing: 8)
    for control in [recorder, reset, toggle] as [NSView] {
      control.setContentHuggingPriority(.required, for: .horizontal)
      control.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    row.setCustomSpacing(14, after: reset)
    row.heightAnchor.constraint(equalToConstant: 38).isActive = true
    return row
  }

  private func showResult(_ result: Result<Void, HotkeyConflict>, success: String) {
    switch result {
    case .success:
      setStatus(success)
    case .failure(let conflict):
      NSSound.beep()
      setStatus(conflict.message, error: true)
    }
  }

  private func setStatus(_ message: String, error: Bool = false) {
    statusLabel.stringValue = message
    statusLabel.textColor = error ? .systemRed : SettingsStyle.secondary
    NSAccessibility.post(element: statusLabel, notification: .valueChanged)
  }
}
