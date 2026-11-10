import AppKit
import Combine
import ISS

/// Status item and its card-style panel.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
  private(set) var statusItem: NSStatusItem!
  private var panel: MenuPanelWindow?
  private var cachedSpaceInfo: ISSSpaceInfo?
  private var refreshWorkItem: DispatchWorkItem?
  private var closedAt = Date.distantPast
  private var outsideClickMonitor: Any?
  private var modeObserver: NSObjectProtocol?
  private var speedControl: SettingsSegmented?
  private let width: CGFloat = 304
  private let radius: CGFloat = 18

  private lazy var baseStatusImage: NSImage? = {
    let image = NSImage(
      systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: Constants.appName)
    image?.isTemplate = true
    return image
  }()

  weak var delegate: MenuBarControllerDelegate?

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel)
    // Opens on press, like a menu.
    statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    statusItem.button?.setAccessibilityLabel(Constants.appName)
    updateStatusItemAppearance()
    modeObserver = NotificationCenter.default.addObserver(
      forName: SwitchingMode.didChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.speedControl?.selected = SwitchingMode.current().segment }
    }
  }

  @objc func togglePanel() {
    if panel?.isVisible == true {
      closePanel()
      return
    }
    // A press on the item first closes the open panel by resigning key.
    guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
    delegate?.menuBarControllerDidRequestRefresh(self)
    openPanel()
  }

  private func openPanel() {
    let panel = makePanel()
    self.panel = panel
    let room = MenuPanelBackdrop.room
    let fitting = panel.contentView?.fittingSize ?? NSSize(width: width + room * 2, height: 400)
    let height = fitting.height - room * 2
    panel.setContentSize(fitting)
    let screen = statusItem.button?.window?.screen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    var origin = NSPoint(x: visible.maxX - width - 10, y: visible.maxY - height - 6)
    if let frame = statusItem.button?.window?.frame, frame.minX > 0 {
      origin = NSPoint(x: frame.midX - width / 2, y: frame.minY - height - 6)
    }
    origin.x = min(max(origin.x, visible.minX + 10), visible.maxX - width - 10)
    panel.setFrameOrigin(NSPoint(x: origin.x - room, y: origin.y - room))
    panel.makeKeyAndOrderFront(nil)
    // With Full Keyboard Access, AppKit would otherwise focus the Space tiles on opening.
    if panel.firstResponder is NSView { panel.makeFirstResponder(nil) }
    statusItem.button?.highlight(true)
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.closePanel() }
    }
  }

  func closePanel() {
    guard let panel else { return }
    self.panel = nil
    speedControl = nil
    closedAt = Date()
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
    statusItem.button?.highlight(false)
    panel.delegate = nil
    panel.orderOut(nil)
  }

  func windowDidResignKey(_ notification: Notification) { closePanel() }

  private func makePanel() -> MenuPanelWindow {
    let panel = MenuPanelWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
    panel.delegate = self
    panel.onClose = { [weak self] in self?.closePanel() }
    panel.keyEquivalents = [
      ",": { [weak self] in self?.openSettings() },
      "q": { NSApp.terminate(nil) },
    ]
    let backdrop = MenuPanelBackdrop(makeContent(), radius: radius)
    backdrop.onClickOutside = { [weak self] in self?.closePanel() }
    panel.contentView = backdrop
    panel.setAccessibilityLabel(Constants.appName)
    return panel
  }

  private func makeContent() -> NSView {
    let surface = SettingsFill(SettingsStyle.card, radius: radius)

    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
    let info = cachedSpaceInfo.flatMap { $0.spaceCount > 0 ? $0 : nil }
    let location = info.map { "Space \($0.currentIndex + 1) of \($0.spaceCount)" } ?? "Spaces unavailable"
    let names = SettingsDesign.stack([
      SettingsDesign.text(Constants.appName, weight: .semibold, color: SettingsStyle.label),
      SettingsDesign.text(location, size: 11, color: SettingsStyle.secondary),
    ], spacing: 0)
    let header = SettingsDesign.stack([icon, names, NSView()], vertical: false, spacing: 9)

    var top: [NSView] = [header]
    if let info {
      top.append(MenuSpacePicker(space: Int(info.currentIndex) + 1, total: Int(info.spaceCount)) {
        [weak self] space in
        guard let self else { return }
        self.closePanel()
        self.delegate?.menuBarController(self, didRequestSwitchToSpaceAtIndex: UInt32(space - 1))
      })
    }
    let speed = SettingsSegmented(titles: SwitchingMode.titles, selected: SwitchingMode.current().segment,
                                  size: .compact, label: "Switching speed")
    speed.onChange = { segment in
      if let mode = SwitchingMode(segment: segment) { SwitchingMode.select(mode) }
    }
    speedControl = speed
    top.append(speed)
    let topStack = SettingsDesign.stack(top, spacing: 10)
    topStack.setCustomSpacing(12, after: header)
    for view in topStack.arrangedSubviews {
      view.widthAnchor.constraint(equalTo: topStack.widthAnchor).isActive = true
    }

    let line = SettingsFill(SettingsStyle.divider)
    line.heightAnchor.constraint(equalToConstant: 1).isActive = true

    let updates = MenuPanelRow("Check for Updates…") { [weak self] in
      self?.closePanel()
      UpdaterManager.shared.checkForUpdates(nil)
    }
    updates.isEnabled = UpdaterManager.shared.canCheckForUpdates
    let rows = SettingsDesign.stack([
      MenuPanelRow("Settings…", shortcut: "⌘,") { [weak self] in self?.openSettings() },
      updates,
      MenuPanelRow("About \(Constants.appName)") { [weak self] in
        self?.closePanel()
        Self.openAbout()
      },
      MenuPanelRow("Quit \(Constants.appName)", shortcut: "⌘Q") { NSApp.terminate(nil) },
    ], spacing: 0)
    for view in rows.arrangedSubviews { view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }

    [topStack, line, rows].forEach { surface.addSubview($0) }
    NSLayoutConstraint.activate([
      surface.widthAnchor.constraint(equalToConstant: width),
      topStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
      topStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14),
      topStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
      line.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 12),
      line.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14),
      line.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
      rows.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 6),
      rows.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 6),
      rows.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -6),
      rows.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -6),
    ])
    return surface
  }

  private func openSettings() {
    closePanel()
    delegate?.menuBarControllerDidRequestPreferences(self)
  }

  static func openAbout() {
    NSApp.activate(ignoringOtherApps: true)
    var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
    if let gitHash = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String {
      options[.version] = "\(gitHash)"
    }
    options[.credits] = NSAttributedString(
      string: "Based on InstantSpaceSwitcher by jurplel (MIT). Original Maccelerate contributions: MIT License. Full licenses and attribution are included in the app bundle.")
    NSApp.orderFrontStandardAboutPanel(options: options)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  func updateWithSpaceInfo(_ info: ISSSpaceInfo?) {
    cachedSpaceInfo = info
    updateStatusItemAppearance()
  }

  func scheduleRefresh(after delay: TimeInterval) {
    refreshWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.delegate?.menuBarControllerDidRequestRefresh(self)
    }
    refreshWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func updateStatusItemAppearance() {
    guard let button = statusItem?.button else { return }
    button.font = nil
    button.title = ""
    button.imagePosition = .imageOnly
    let icon = cachedSpaceInfo.flatMap { MenuBarIconRenderer.renderIcon(for: $0) } ?? baseStatusImage
    icon?.isTemplate = true
    button.image = icon
  }
}

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController)
  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32)
  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController)
}
