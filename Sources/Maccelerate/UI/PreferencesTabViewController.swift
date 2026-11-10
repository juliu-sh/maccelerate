import AppKit
import ISS

final class PreferencesTabViewController: NSViewController {
  private let pages: [NSViewController] = [
    GeneralSettingsViewController(), KeyboardShortcutsViewController(),
    AppearanceSettingsViewController(), StatisticsViewController(),
  ]
  private let navigation = SettingsSegmented(titles: ["Switching", "Shortcuts", "Appearance", "Statistics"],
                                             selected: 0, size: .tabs, label: "Settings section")
  private let content = NSView()
  private let permissionSurface = SettingsSurface()
  private let permissionWarningTint = NSColor(name: nil) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return NSColor.systemRed.withAlphaComponent(dark ? 0.16 : 0.08)
  }
  private let permissionLabel = SettingsDesign.text("", size: 11, color: SettingsStyle.secondary)
  private lazy var permissionButton = SettingsButton("Open System Settings") { [weak self] in
    self?.openPermissions()
  }
  private var activationObserver: NSObjectProtocol?
  private var inputObserver: NSObjectProtocol?

  override func loadView() {
    let background = SettingsSurface()
    background.fillColor = SettingsStyle.canvas
    background.radius = 0
    view = background
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
    let brand = SettingsDesign.stack([
      SettingsDesign.text(Constants.appName, size: 15, weight: .semibold, color: SettingsStyle.label),
      SettingsDesign.text("Your Spaces. At your pace.", size: 12, color: SettingsStyle.secondary),
    ], spacing: 1)
    let header = SettingsDesign.stack([icon, brand, NSView()], vertical: false, spacing: 10)
    navigation.onChange = { [weak self] in self?.showPage($0) }
    let top = SettingsDesign.stack([header, navigation], spacing: 16)
    view.addSubview(top)

    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)
    let footer = SettingsDesign.stack([permissionLabel, NSView(), permissionButton],
                                      vertical: false, spacing: 12)
    permissionSurface.radius = 0
    permissionSurface.fillColor = .clear
    permissionSurface.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(permissionSurface)
    view.addSubview(footer)
    let line = SettingsFill(SettingsStyle.divider)
    view.addSubview(line)
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: view.topAnchor, constant: 36),
      top.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      header.widthAnchor.constraint(equalTo: top.widthAnchor),
      navigation.widthAnchor.constraint(equalTo: top.widthAnchor),
      content.topAnchor.constraint(equalTo: top.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      content.bottomAnchor.constraint(equalTo: line.topAnchor),
      line.heightAnchor.constraint(equalToConstant: 1),
      line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      line.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
      permissionSurface.topAnchor.constraint(equalTo: line.bottomAnchor),
      permissionSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      permissionSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      permissionSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
      footer.heightAnchor.constraint(equalToConstant: 28),
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

  /// Opens a page from outside, for example from the preview build.
  func select(page index: Int) {
    guard pages.indices.contains(index) else { return }
    navigation.selected = index
    showPage(index)
  }

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
    permissionLabel.textColor = connected ? SettingsStyle.secondary : SettingsStyle.label
    permissionButton.isHidden = connected
  }

  private func openPermissions() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
    NSWorkspace.shared.open(url)
  }
}
