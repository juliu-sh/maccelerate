import AppKit

final class PreferencesTabViewController: NSViewController {
  private let pages: [NSViewController] = [
    GeneralSettingsViewController(), KeyboardShortcutsViewController(),
  ]
  private let navigation = NSSegmentedControl(labels: ["Switching", "Shortcuts"],
                                             trackingMode: .selectOne, target: nil, action: nil)
  private let content = NSView()
  private let permissionLabel = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)
  private let permissionButton = NSButton(title: "Open System Settings", target: nil, action: nil)
  private var activationObserver: NSObjectProtocol?

  override func loadView() {
    let background = SettingsSurface()
    background.fillColor = SettingsDesign.canvas
    background.radius = 0
    view = background
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let brand = SettingsDesign.stack([
      SettingsDesign.text(Constants.appName, size: 19, weight: .semibold),
      SettingsDesign.text("Your Spaces. At your pace.", size: 12, color: .secondaryLabelColor),
    ], spacing: 3)
    let header = SettingsDesign.stack([icon, brand, NSView()], vertical: false, spacing: 12)
    navigation.target = self
    navigation.action = #selector(changePage)
    navigation.segmentStyle = .rounded
    navigation.controlSize = .large
    navigation.selectedSegment = 0
    navigation.setAccessibilityLabel("Settings section")
    let top = SettingsDesign.stack([header, navigation], spacing: 22)
    view.addSubview(top)
    header.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true
    navigation.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true
    navigation.heightAnchor.constraint(equalToConstant: 36).isActive = true
    navigation.segmentDistribution = .fillEqually

    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)
    permissionButton.bezelStyle = .inline
    permissionButton.font = .systemFont(ofSize: 11, weight: .medium)
    permissionButton.target = self
    permissionButton.action = #selector(openPermissions)
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let versionLabel = SettingsDesign.text("Version \(version)", size: 11, color: .secondaryLabelColor)
    versionLabel.setContentHuggingPriority(.required, for: .horizontal)
    versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    let footer = SettingsDesign.stack([permissionLabel, NSView(), permissionButton, versionLabel],
                                      vertical: false, spacing: 12)
    view.addSubview(footer)
    let divider = NSBox()
    divider.boxType = .separator
    divider.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(divider)
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: view.topAnchor, constant: 38),
      top.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      content.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 0),
      content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      content.bottomAnchor.constraint(equalTo: divider.topAnchor),
      divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      divider.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
      footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
      footer.heightAnchor.constraint(equalToConstant: 20),
    ])
    pages.forEach { addChild($0) }
    showPage(0)
    refreshPermissionStatus()
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.refreshPermissionStatus() }
  }

  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
  }

  @objc private func changePage(_ sender: NSSegmentedControl) { showPage(sender.selectedSegment) }

  private func showPage(_ index: Int) {
    guard pages.indices.contains(index) else { return }
    ShortcutRecorderControl.cancelActiveRecording()
    content.subviews.forEach { $0.removeFromSuperview() }
    SettingsDesign.pin(pages[index].view, to: content)
  }

  private func refreshPermissionStatus() {
    let trusted = AXIsProcessTrusted()
    permissionLabel.stringValue = trusted ? "Accessibility connected · Changes save automatically"
      : "Accessibility access is needed to switch Spaces."
    permissionButton.isHidden = trusted
  }

  @objc private func openPermissions() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
    NSWorkspace.shared.open(url)
  }
}
