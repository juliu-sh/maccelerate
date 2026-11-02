import AppKit
import Combine

private class RecordingView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func becomeFirstResponder() -> Bool { true }
}

final class KeyboardShortcutsViewController: NSViewController {
  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private let systemSwitch = NSSwitch()
  private let systemSummary = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)
  private let additionalSwitch = NSSwitch()
  private let filter = NSSegmentedControl(labels: ["Navigation", "Direct access"],
                                         trackingMode: .selectOne, target: nil, action: nil)
  private let statusLabel = SettingsDesign.text("Click a shortcut to record. Press Esc to cancel.", size: 11, color: .secondaryLabelColor)
  /// Everything below the global switch; hidden while additional shortcuts are off.
  private let additionalDetails = SettingsDesign.stack(spacing: 12)
  private let shortcutRows = SettingsDesign.stack(spacing: 0)

  private var shortcuts: [HotkeyIdentifier] = []

  override func loadView() {
    view = RecordingView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let intro = SettingsDesign.heading("Make it muscle memory.", subtitle: "Your favorite actions, one shortcut away.")
    let content = SettingsDesign.stack([intro, makeSystemSection(), makeAdditionalSection()], spacing: 18)
    SettingsDesign.page(content, in: view)
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
  private func makeSystemSection() -> NSView {
    systemSwitch.target = self
    systemSwitch.action = #selector(systemShortcutsChanged)
    systemSwitch.setAccessibilityLabel("Accelerate macOS shortcuts")
    systemSummary.lineBreakMode = .byWordWrapping
    systemSummary.maximumNumberOfLines = 2
    let title = SettingsDesign.text("Accelerate macOS shortcuts", weight: .medium)
    let change = NSButton(title: "Change in System Settings…", target: self,
                          action: #selector(openSystemShortcuts))
    change.bezelStyle = .inline
    change.controlSize = .small
    let texts = SettingsDesign.stack([title, systemSummary, change], spacing: 4)
    texts.alignment = .leading
    let row = SettingsDesign.stack([SymbolTile(symbol: "keyboard"), texts, NSView(), systemSwitch],
                                   vertical: false, spacing: 12)
    row.alignment = .centerY
    systemSwitch.setContentHuggingPriority(.required, for: .horizontal)
    return SettingsDesign.section("macOS shortcuts", content: SettingsDesign.card([row], padding: 12))
  }

  private func makeAdditionalSection() -> NSView {
    additionalSwitch.target = self
    additionalSwitch.action = #selector(additionalShortcutsChanged)
    additionalSwitch.setAccessibilityLabel("Use additional shortcuts")
    let toggleRow = SettingsDesign.row("Use additional shortcuts",
                                       detail: "Your own key combinations, on top of macOS’s.",
                                       symbol: "command", control: additionalSwitch)

    filter.segmentStyle = .rounded
    filter.target = self
    filter.action = #selector(filterChanged)
    filter.setAccessibilityLabel("Shortcut category")
    filter.setWidth(120, forSegment: 0)
    filter.setWidth(120, forSegment: 1)
    let reset = SettingsDesign.button("Restore defaults…", target: self, action: #selector(resetAllShortcuts))
    reset.controlSize = .regular
    let controls = SettingsDesign.stack([filter, NSView(), reset], vertical: false, spacing: 12)

    let divider = NSBox()
    divider.boxType = .separator
    for child in [divider, controls, shortcutRows, statusLabel] {
      additionalDetails.addArrangedSubview(child)
    }
    additionalDetails.setCustomSpacing(4, after: controls)
    additionalDetails.setCustomSpacing(6, after: shortcutRows)
    for child in [divider, controls, shortcutRows, statusLabel] {
      child.widthAnchor.constraint(equalTo: additionalDetails.widthAnchor).isActive = true
    }
    let content = SettingsDesign.stack([toggleRow, additionalDetails], spacing: 12)
    for child in [toggleRow, additionalDetails] {
      child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    return SettingsDesign.section("Additional shortcuts", content: SettingsDesign.card([content], padding: 12))
  }

  private func loadSystemShortcuts() {
    systemSwitch.state = SystemSpaceShortcuts.isAccelerationEnabled ? .on : .off
    systemSummary.stringValue = SystemSpaceShortcuts.summary(of: SystemSpaceShortcuts.current())
    (NSApp.delegate as? AppDelegate)?.applySystemShortcuts()
  }

  @objc private func systemShortcutsChanged(_ sender: NSSwitch) {
    UserDefaults.standard.set(sender.state == .on, forKey: SystemSpaceShortcuts.enabledKey)
    (NSApp.delegate as? AppDelegate)?.applySystemShortcuts()
  }

  @objc private func openSystemShortcuts() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    else { return }
    NSWorkspace.shared.open(url)
  }

  @objc private func additionalShortcutsChanged(_ sender: NSSwitch) {
    ShortcutRecorderControl.cancelActiveRecording()
    store.setAdditionalShortcutsEnabled(sender.state == .on)
  }

  @objc private func filterChanged() {
    ShortcutRecorderControl.cancelActiveRecording()
    loadShortcuts()
  }

  private func loadShortcuts() {
    additionalSwitch.state = store.additionalShortcutsEnabled ? .on : .off
    additionalDetails.isHidden = !store.additionalShortcutsEnabled
    if filter.selectedSegment < 0 { filter.selectedSegment = 0 }
    let navigation: [HotkeyIdentifier] = [.left, .right, .lastSpace, .missionControl, .appExpose]
    shortcuts = filter.selectedSegment == 0 ? navigation : HotkeyIdentifier.allCases.filter { !navigation.contains($0) }
    shortcutRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, identifier) in shortcuts.enumerated() {
      if index > 0 {
        let divider = NSBox()
        divider.boxType = .separator
        shortcutRows.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: shortcutRows.widthAnchor).isActive = true
      }
      let row = makeShortcutRow(identifier, index: index)
      shortcutRows.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: shortcutRows.widthAnchor).isActive = true
    }
    if let warning = store.conflictWarning { setStatus(warning, error: true) }
  }

  private func makeShortcutRow(_ identifier: HotkeyIdentifier, index: Int) -> NSView {
    let isEnabled = store.isEnabled(identifier)
    let name = SettingsDesign.text(identifier.displayName, weight: .medium,
                                   color: isEnabled ? .labelColor : .disabledControlTextColor)

    let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
    recorder.currentShortcut = store.combination(for: identifier)
    recorder.isEnabled = isEnabled
    recorder.setAccessibilityLabel("Shortcut for \(identifier.displayName)")
    recorder.onRecordingComplete = { [weak self] combination in
      self?.handleRecordingResult(combination, for: identifier)
    }
    recorder.translatesAutoresizingMaskIntoConstraints = false
    recorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
    recorder.heightAnchor.constraint(equalToConstant: 28).isActive = true

    let resetButton = NSButton(
      image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")!,
      target: self, action: #selector(resetShortcut(_:)))
    resetButton.isBordered = false
    resetButton.tag = index
    resetButton.toolTip = "Restore default for \(identifier.displayName)"
    resetButton.setAccessibilityLabel("Restore default for \(identifier.displayName)")
    resetButton.isEnabled = isEnabled
    resetButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

    let toggle = NSSwitch()
    toggle.target = self
    toggle.action = #selector(toggleEnabled(_:))
    toggle.setAccessibilityLabel("Enable \(identifier.displayName)")
    toggle.state = isEnabled ? .on : .off
    toggle.tag = index

    let row = SettingsDesign.stack([name, NSView(), recorder, resetButton, toggle],
                                   vertical: false, spacing: 10)
    row.alignment = .centerY
    for control in [recorder, resetButton, toggle] as [NSView] {
      control.setContentHuggingPriority(.required, for: .horizontal)
      control.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    row.setCustomSpacing(16, after: resetButton)
    row.heightAnchor.constraint(equalToConstant: 40).isActive = true
    return row
  }

  @objc private func resetShortcut(_ sender: NSButton) {
    let row = sender.tag
    guard row < shortcuts.count else { return }

    let identifier = shortcuts[row]
    showResult(store.resetShortcut(for: identifier),
               success: "Default shortcut restored for \(identifier.displayName).")
  }

  @objc private func resetAllShortcuts() {
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

  @objc private func toggleEnabled(_ sender: NSSwitch) {
    let row = sender.tag
    guard row < shortcuts.count else { return }

    let identifier = shortcuts[row]
    let result = store.setEnabled(sender.state == .on, for: identifier)
    sender.state = store.isEnabled(identifier) ? .on : .off
    showResult(result, success: "Shortcut \(store.isEnabled(identifier) ? "enabled" : "disabled").")
  }

  private func handleRecordingResult(
    _ combination: HotkeyCombination, for identifier: HotkeyIdentifier
  ) {
    showResult(store.update(combination, for: identifier),
               success: "Shortcut saved for \(identifier.displayName).")
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
    statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
    NSAccessibility.post(element: statusLabel, notification: .valueChanged)
  }
}
