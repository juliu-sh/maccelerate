import AppKit
import Combine

private class RecordingView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func becomeFirstResponder() -> Bool { true }
}

final class KeyboardShortcutsViewController: NSViewController {
  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private let filter = NSSegmentedControl(labels: ["Navigation", "Direct access"],
                                         trackingMode: .selectOne, target: nil, action: nil)
  private let statusLabel = SettingsDesign.text("Click a shortcut to record. Press Esc to cancel.", size: 11, color: .secondaryLabelColor)

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private struct ShortcutRow {
    let identifier: HotkeyIdentifier
    let name: String
    var combination: HotkeyCombination
    var isEnabled: Bool
  }

  private var shortcuts: [ShortcutRow] = []

  override func loadView() {
    view = RecordingView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupTableView()
    loadShortcuts()
    bindStore()
  }

  private func setupTableView() {
    let intro = SettingsDesign.heading("Make it muscle memory.", subtitle: "Your favorite actions, one shortcut away.")
    filter.selectedSegment = 0
    filter.segmentStyle = .rounded
    filter.controlSize = .large
    filter.target = self
    filter.action = #selector(filterChanged)
    filter.setAccessibilityLabel("Shortcut category")
    filter.setWidth(144, forSegment: 0)
    filter.setWidth(144, forSegment: 1)

    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.width = 240
    nameColumn.minWidth = 180
    let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
    shortcutColumn.width = 218
    shortcutColumn.minWidth = 218
    shortcutColumn.maxWidth = 218
    let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
    enabledColumn.width = 76
    enabledColumn.minWidth = 76
    enabledColumn.maxWidth = 76
    [nameColumn, shortcutColumn, enabledColumn].forEach { tableView.addTableColumn($0) }
    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 58
    tableView.headerView = nil
    tableView.selectionHighlightStyle = .none
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = [.solidHorizontalGridLineMask]
    tableView.gridColor = .separatorColor
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    tableView.setAccessibilityLabel("Keyboard shortcuts")

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    let card = SettingsSurface()
    SettingsDesign.pin(scrollView, to: card, inset: 10)
    card.translatesAutoresizingMaskIntoConstraints = false

    let reset = SettingsDesign.button("Restore defaults…", target: self, action: #selector(resetAllShortcuts))
    let bottom = SettingsDesign.stack([statusLabel, NSView(), reset], vertical: false, spacing: 12)
    let tip = SettingsDesign.text("Turn off any shortcuts you don’t use. Your key combinations stay saved.", size: 11, color: .secondaryLabelColor)
    [intro, filter, card, bottom, tip].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }
    NSLayoutConstraint.activate([
      intro.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
      intro.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      intro.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      filter.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 22),
      filter.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
      filter.heightAnchor.constraint(equalToConstant: 32),
      card.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: 18),
      card.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
      card.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
      card.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -18),
      bottom.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
      bottom.bottomAnchor.constraint(equalTo: tip.topAnchor, constant: -16),
      tip.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
      tip.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
      tip.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -26),
    ])
  }

  @objc private func filterChanged() {
    ShortcutRecorderControl.cancelActiveRecording()
    loadShortcuts()
    scrollView.contentView.scroll(to: .zero)
  }

  private func loadShortcuts() {
    let navigation: [HotkeyIdentifier] = [.left, .right, .lastSpace, .missionControl, .appExpose]
    let identifiers = filter.selectedSegment == 0 ? navigation : HotkeyIdentifier.allCases.filter { !navigation.contains($0) }
    shortcuts = identifiers.map { id in
      ShortcutRow(
        identifier: id,
        name: id.displayName,
        combination: store.combination(for: id),
        isEnabled: store.isEnabled(id)
      )
    }
    tableView.reloadData()
    if let warning = store.conflictWarning { setStatus(warning, error: true) }
  }

  private func bindStore() {
    store.$leftHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$rightHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$missionControlHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$appExposeHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space1Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space2Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space3Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space4Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space5Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space6Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space7Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space8Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space9Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space10Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$spaceLastSpaceHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$enabledStates.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
  }
}

extension KeyboardShortcutsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return shortcuts.count
  }
}

extension KeyboardShortcutsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let shortcut = shortcuts[row]

    if tableColumn?.identifier.rawValue == "enabled" {
      let cellView = NSTableCellView()
      let checkbox = NSSwitch()
      checkbox.target = self
      checkbox.action = #selector(toggleEnabled(_:))
      checkbox.setAccessibilityLabel("Enable \(shortcut.name)")
      checkbox.state = shortcut.isEnabled ? .on : .off
      checkbox.tag = row
      checkbox.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(checkbox)

      NSLayoutConstraint.activate([
        checkbox.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
        checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    } else if tableColumn?.identifier.rawValue == "name" {
      let cellView = NSTableCellView()
      let textField = SettingsDesign.text(shortcut.name, size: 13, weight: .medium)
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.textColor = shortcut.isEnabled ? .labelColor : .disabledControlTextColor
      cellView.addSubview(textField)
      cellView.textField = textField

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 12),
        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    } else if tableColumn?.identifier.rawValue == "shortcut" {
      let cellView = NSView()

      let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 150, height: 34))
      recorder.currentShortcut = shortcut.combination
      recorder.translatesAutoresizingMaskIntoConstraints = false
      recorder.isEnabled = shortcut.isEnabled
      recorder.setAccessibilityLabel("Shortcut for \(shortcut.name)")
      recorder.onRecordingComplete = { [weak self] combination in
        self?.handleRecordingResult(combination, for: shortcut.identifier)
      }
      recorder.onRecordingCancelled = {
        print("[KeyboardShortcuts] Recording cancelled")
      }
      cellView.addSubview(recorder)

      let resetButton = NSButton(
        image: NSImage(
          systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")!,
        target: self, action: #selector(resetShortcut(_:)))
      resetButton.bezelStyle = .rounded
      resetButton.isBordered = false
      resetButton.tag = row
      resetButton.toolTip = "Restore default for \(shortcut.name)"
      resetButton.setAccessibilityLabel("Restore default for \(shortcut.name)")
      resetButton.isEnabled = shortcut.isEnabled
      resetButton.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(resetButton)

      NSLayoutConstraint.activate([
        recorder.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        recorder.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        recorder.widthAnchor.constraint(equalToConstant: 150),
        recorder.heightAnchor.constraint(equalToConstant: 34),

        resetButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 8),
        resetButton.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        resetButton.widthAnchor.constraint(equalToConstant: 36),
        resetButton.heightAnchor.constraint(equalToConstant: 36),
      ])

      return cellView
    }

    return nil
  }

  @objc private func resetShortcut(_ sender: NSButton) {
    let row = sender.tag
    guard row < shortcuts.count else { return }

    let identifier = shortcuts[row].identifier
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

    let identifier = shortcuts[row].identifier
    let result = store.setEnabled(sender.state == .on, for: identifier)
    sender.state = store.isEnabled(identifier) ? .on : .off
    shortcuts[row].isEnabled = store.isEnabled(identifier)
    tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
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
