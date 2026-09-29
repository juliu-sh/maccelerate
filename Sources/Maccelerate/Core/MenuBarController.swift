import AppKit
import Combine
import ISS

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private(set) var statusItem: NSStatusItem!
  private var leftMenuItem: NSMenuItem?
  private var rightMenuItem: NSMenuItem?
  private var missionControlMenuItem: NSMenuItem?
  private var appExposeMenuItem: NSMenuItem?
  private var spacesMenuItem: NSMenuItem?
  private var cachedSpaceInfo: ISSSpaceInfo?
  private let menuSummary = MenuSummaryView()
  private var refreshWorkItem: DispatchWorkItem?
  private var updaterSubscription: AnyCancellable?

  private lazy var baseStatusImage: NSImage? = {
    let image = NSImage(
      systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: Constants.appName)
    image?.isTemplate = true
    return image
  }()

  weak var delegate: MenuBarControllerDelegate?

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.menu = createMenu()
    updateStatusItemAppearance()
  }

  private func createMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    menu.minimumWidth = 290
    let summaryItem = NSMenuItem()
    summaryItem.view = menuSummary
    menu.addItem(summaryItem)
    menu.addItem(.separator())

    let leftItem = NSMenuItem(
      title: "Switch Left", action: #selector(switchLeft(_:)), keyEquivalent: "")
    leftItem.target = self
    leftItem.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)
    menu.addItem(leftItem)
    leftMenuItem = leftItem

    let rightItem = NSMenuItem(
      title: "Switch Right", action: #selector(switchRight(_:)), keyEquivalent: "")
    rightItem.target = self
    rightItem.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
    menu.addItem(rightItem)
    rightMenuItem = rightItem

    menu.addItem(NSMenuItem.separator())

    let missionControlItem = NSMenuItem(
      title: "Mission Control", action: #selector(showMissionControl(_:)), keyEquivalent: "")
    missionControlItem.target = self
    missionControlItem.image = NSImage(
      systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
    menu.addItem(missionControlItem)
    missionControlMenuItem = missionControlItem

    let appExposeItem = NSMenuItem(
      title: "App Exposé", action: #selector(showAppExpose(_:)), keyEquivalent: "")
    appExposeItem.target = self
    appExposeItem.image = NSImage(
      systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
    menu.addItem(appExposeItem)
    appExposeMenuItem = appExposeItem

    menu.addItem(NSMenuItem.separator())

    let spacesItem = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
    let spacesSubmenu = NSMenu(title: "Spaces")
    spacesSubmenu.delegate = self
    spacesSubmenu.autoenablesItems = false
    spacesItem.submenu = spacesSubmenu
    spacesItem.image = NSImage(
      systemSymbolName: "square.and.line.vertical.and.square", accessibilityDescription: nil)
    menu.addItem(spacesItem)
    spacesMenuItem = spacesItem

    menu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.keyEquivalentModifierMask = [.command]
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    menu.addItem(preferencesItem)

    menu.addItem(NSMenuItem.separator())

    let aboutItem = NSMenuItem(
      title: "About Maccelerate", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    menu.addItem(aboutItem)

    let updateItem = NSMenuItem(title: "Check for Updates…",
      action: #selector(UpdaterManager.checkForUpdates(_:)), keyEquivalent: "")
    updateItem.target = UpdaterManager.shared
    updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
    menu.addItem(updateItem)
    updaterSubscription = UpdaterManager.shared.$canCheckForUpdates.sink { [weak updateItem] available in
      updateItem?.isEnabled = available
    }

    let quitItem = NSMenuItem(
      title: "Quit Maccelerate", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quitItem.target = NSApp
    menu.addItem(quitItem)

    return menu
  }

  @objc private func switchLeft(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestSwitchLeft(self)
  }

  @objc private func switchRight(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestSwitchRight(self)
  }

  @objc private func showMissionControl(_ sender: Any?) {
    delegate?.menuBarController(
      self, didRequestOverlay: ISSOverlayModeMissionControl, sourceEvent: NSApp.currentEvent)
  }

  @objc private func showAppExpose(_ sender: Any?) {
    delegate?.menuBarController(
      self, didRequestOverlay: ISSOverlayModeAppExpose, sourceEvent: NSApp.currentEvent)
  }

  @objc private func openPreferences(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestPreferences(self)
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)

    var options: [NSApplication.AboutPanelOptionKey: Any] = [:]

    if let gitHash = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String {
      options[.version] = "\(gitHash)"
    }
    options[.credits] = NSAttributedString(
      string: "Based on InstantSpaceSwitcher by jurplel (MIT). Original Maccelerate contributions: MIT License. Full licenses and attribution are included in the app bundle and disk image.")

    NSApp.orderFrontStandardAboutPanel(options: options)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  @objc private func switchToSpace(_ sender: NSMenuItem) {
    let targetIndex = UInt32(sender.tag)
    delegate?.menuBarController(self, didRequestSwitchToSpaceAtIndex: targetIndex)
  }

  func updateWithSpaceInfo(_ info: ISSSpaceInfo?) {
    cachedSpaceInfo = info
    menuSummary.update(info)
    updateMenuState()
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

  private func updateMenuState() {
    if let info = cachedSpaceInfo {
      leftMenuItem?.isEnabled = info.currentIndex > 0
      rightMenuItem?.isEnabled = info.currentIndex + 1 < info.spaceCount
    } else {
      leftMenuItem?.isEnabled = true
      rightMenuItem?.isEnabled = true
    }

    updateSpacesMenuItems()
    updateStatusItemAppearance()
  }

  private func updateSpacesMenuItems() {
    guard let submenu = spacesMenuItem?.submenu else { return }
    submenu.removeAllItems()

    guard let info = cachedSpaceInfo, info.spaceCount > 0 else {
      let item = NSMenuItem(title: "No accessible spaces", action: nil, keyEquivalent: "")
      item.isEnabled = false
      submenu.addItem(item)
      return
    }

    let count = Int(info.spaceCount)
    let store = HotkeyStore.shared
    for index in 0..<count {
      let title = "Space \(index + 1)"
      let item = NSMenuItem(title: title, action: #selector(switchToSpace(_:)), keyEquivalent: "")
      
      // Sync customized shortcuts
      if let identifier = identifierForSpace(index + 1) {
        let comb = store.combination(for: identifier)
        item.keyEquivalent = comb.keyEquivalent
        item.keyEquivalentModifierMask = comb.cocoaModifierFlags
      }

      item.tag = index
      item.target = self
      item.state = index == Int(info.currentIndex) ? .on : .off
      submenu.addItem(item)
    }
  }

  private func identifierForSpace(_ number: Int) -> HotkeyIdentifier? {
    switch number {
    case 1: return .space1
    case 2: return .space2
    case 3: return .space3
    case 4: return .space4
    case 5: return .space5
    case 6: return .space6
    case 7: return .space7
    case 8: return .space8
    case 9: return .space9
    case 10: return .space10
    default: return nil
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
      scheduleRefresh(after: 0.05)
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
      scheduleRefresh(after: 0.05)
    }
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    guard menu === statusItem.menu else { return }
    if item === missionControlMenuItem {
      iss_arm_overlay_menu(ISSOverlayModeMissionControl)
    } else if item === appExposeMenuItem {
      iss_arm_overlay_menu(ISSOverlayModeAppExpose)
    } else {
      iss_disarm_overlay_menu()
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    if menu === statusItem.menu {
      iss_disarm_overlay_menu()
    }
  }

  private func updateStatusItemAppearance() {
    guard let button = statusItem.button else { return }

    button.font = nil
    button.title = ""
    button.imagePosition = .imageOnly

    let icon: NSImage?
    if let info = cachedSpaceInfo {
      icon = MenuBarIconRenderer.renderIcon(for: info)
    } else {
      icon = nil
    }

    let finalIcon = icon ?? baseStatusImage
    finalIcon?.isTemplate = true
    button.image = finalIcon
  }

  func applyHotkey(_ combination: HotkeyCombination, to identifier: HotkeyIdentifier) {
    let menuItem: NSMenuItem?
    switch identifier {
    case .left: menuItem = leftMenuItem
    case .right: menuItem = rightMenuItem
    case .missionControl: menuItem = missionControlMenuItem
    case .appExpose: menuItem = appExposeMenuItem
    default: return
    }
    guard let menuItem else { return }
    if identifier == .missionControl || identifier == .appExpose {
      // The event tap owns these shortcuts on macOS 27. Registering a second
      // AppKit key equivalent can toggle the same overlay twice.
      menuItem.keyEquivalent = ""
      menuItem.keyEquivalentModifierMask = []
      menuItem.toolTip = combination.displayString
      return
    }
    menuItem.keyEquivalent = combination.keyEquivalent
    menuItem.keyEquivalentModifierMask = combination.cocoaModifierFlags
  }
}

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController)
  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController)
  func menuBarController(
    _ controller: MenuBarController, didRequestOverlay mode: ISSOverlayMode,
    sourceEvent: NSEvent?)
  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController)
  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32)
  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController)
}
