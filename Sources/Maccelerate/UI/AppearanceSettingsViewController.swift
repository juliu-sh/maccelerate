import AppKit

final class AppearanceSettingsViewController: NSViewController {
  private let osdSwitch = NSSwitch()
  private let durationPopup = NSPopUpButton()
  private let previewButton = NSButton(title: "Preview", target: nil, action: nil)
  private let preview = SpaceHUDView()
  private let durations = [100, 200, 300, 500, 750, 1000]
  private let defaults = UserDefaults.standard

  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    let intro = SettingsDesign.heading("A little sense of place.", subtitle: "A quiet cue when you arrive at another Space.")
    let canvas = SettingsSurface()
    canvas.fillColor = SettingsDesign.inset
    canvas.radius = 18
    canvas.heightAnchor.constraint(equalToConstant: 138).isActive = true
    preview.translatesAutoresizingMaskIntoConstraints = false
    preview.setSpace("2")
    canvas.addSubview(preview)
    let sampleLabel = SettingsDesign.text("ON-SCREEN PREVIEW", size: 9, weight: .medium, color: .secondaryLabelColor)
    sampleLabel.translatesAutoresizingMaskIntoConstraints = false
    canvas.addSubview(sampleLabel)
    NSLayoutConstraint.activate([
      preview.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      preview.centerYAnchor.constraint(equalTo: canvas.centerYAnchor, constant: -8),
      preview.widthAnchor.constraint(equalToConstant: 196),
      preview.heightAnchor.constraint(equalToConstant: 64),
      sampleLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      sampleLabel.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -18),
    ])
    osdSwitch.target = self
    osdSwitch.action = #selector(osdChanged)
    osdSwitch.setAccessibilityLabel("Show Space indicator")
    durationPopup.addItems(withTitles: durations.map { "\($0) ms" })
    durationPopup.target = self
    durationPopup.action = #selector(durationChanged)
    durationPopup.setAccessibilityLabel("Indicator duration")
    durationPopup.widthAnchor.constraint(equalToConstant: 110).isActive = true
    let rows = SettingsDesign.card([
      SettingsDesign.row("Space indicator", detail: "Show the destination number after switching.",
                         symbol: "rectangle.on.rectangle", control: osdSwitch),
      SettingsDesign.row("Display duration", detail: "How long the indicator stays on screen.",
                         symbol: "timer", control: durationPopup),
    ], padding: 12)
    previewButton.bezelStyle = .rounded
    previewButton.controlSize = .large
    previewButton.target = self
    previewButton.action = #selector(showPreview)
    let previewRow = SettingsDesign.row("Try it on your screen", detail: "Preview the indicator without switching Spaces.", control: previewButton, height: 44)
    let content = SettingsDesign.stack([
      intro, canvas, SettingsDesign.section("On-screen display", content: rows),
      previewRow,
      SettingsDesign.text("Follows your Mac’s appearance and accessibility preferences.", size: 11, color: .secondaryLabelColor),
    ], spacing: 18)
    SettingsDesign.page(content, in: view)
    loadSettings()
  }

  override func viewWillAppear() { super.viewWillAppear(); loadSettings() }

  private func loadSettings() {
    let enabled = defaults.bool(forKey: "showOSD")
    osdSwitch.state = enabled ? .on : .off
    durationPopup.selectItem(at: durations.firstIndex(of: defaults.object(forKey: "osdDurationMs") as? Int ?? 200) ?? 1)
    durationPopup.isEnabled = enabled
  }

  @objc private func osdChanged(_ sender: NSSwitch) {
    defaults.set(sender.state == .on, forKey: "showOSD")
    loadSettings()
  }
  @objc private func durationChanged(_ sender: NSPopUpButton) {
    guard durations.indices.contains(sender.indexOfSelectedItem) else { return }
    defaults.set(durations[sender.indexOfSelectedItem], forKey: "osdDurationMs")
  }
  @objc private func showPreview() { OSDWindow.shared.showPreview() }
}
