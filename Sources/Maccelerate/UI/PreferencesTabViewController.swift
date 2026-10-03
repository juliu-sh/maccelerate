import AppKit
import ISS

final class PreferencesTabViewController: NSViewController {
  private let pages: [NSViewController] = [
    GeneralSettingsViewController(), KeyboardShortcutsViewController(),
  ]
  private let navigation = NSSegmentedControl(labels: ["Switching", "Shortcuts"],
                                             trackingMode: .selectOne, target: nil, action: nil)
  private let content = NSView()
  private let permissionSurface = SettingsSurface()
  private let permissionWarningTint = NSColor(name: nil) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return NSColor.systemRed.withAlphaComponent(dark ? 0.16 : 0.08)
  }
  private let permissionLabel = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)
  private let permissionButton = NSButton(title: "Open System Settings", target: nil, action: nil)
  private var activationObserver: NSObjectProtocol?
  private var inputObserver: NSObjectProtocol?

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
    permissionSurface.radius = 0
    permissionSurface.fillColor = .clear
    permissionSurface.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(permissionSurface)
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
      permissionSurface.topAnchor.constraint(equalTo: divider.bottomAnchor),
      permissionSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      permissionSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      permissionSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
    inputObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("MaccelerateInputConnectionChanged"), object: nil, queue: .main
    ) { [weak self] _ in self?.refreshPermissionStatus() }
  }

  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    if let inputObserver { NotificationCenter.default.removeObserver(inputObserver) }
  }

  @objc private func changePage(_ sender: NSSegmentedControl) { showPage(sender.selectedSegment) }

  private func showPage(_ index: Int) {
    guard pages.indices.contains(index) else { return }
    ShortcutRecorderControl.cancelActiveRecording()
    content.subviews.forEach { $0.removeFromSuperview() }
    SettingsDesign.pin(pages[index].view, to: content)
  }

  private func refreshPermissionStatus() {
    let trusted = iss_has_event_access()
    let requiresRestart = iss_input_requires_restart()
    let connected = trusted && iss_is_active() && !requiresRestart
    if requiresRestart {
      permissionLabel.stringValue = "Input stopped. Check access, then quit and reopen Maccelerate."
    } else if trusted && iss_is_active() {
      permissionLabel.stringValue = "Accessibility connected · Changes save automatically"
    } else if trusted {
      permissionLabel.stringValue = "Input connection unavailable. Quit and reopen Maccelerate."
    } else {
      permissionLabel.stringValue = "Accessibility access is needed to switch Spaces."
    }
    // Draw the warning independently of window activation so it stays visible
    // when macOS dims the controls of an inactive settings window.
    permissionSurface.fillColor = connected ? .clear : permissionWarningTint
    permissionLabel.textColor = connected ? .secondaryLabelColor : .labelColor
    permissionButton.isHidden = connected
  }

  @objc private func openPermissions() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
    NSWorkspace.shared.open(url)
  }
}
