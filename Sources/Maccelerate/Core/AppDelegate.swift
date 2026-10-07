import AppKit
import ApplicationServices
import Combine
import ISS

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let menuBarController = MenuBarController()
  private let updater = UpdaterManager.shared
  private let hotkeyStore = HotkeyStore.shared
  private lazy var preferencesWindowController = PreferencesWindowController()
  private var currentSpaceIndex: UInt32?
  private var lastSpaceIndex: UInt32?
  private var cancellables = Set<AnyCancellable>()
  private var hotkeyRefresh: DispatchWorkItem?
  private var spaceChangeObserver: Any?
  private var appActivationObserver: Any?
  private var appLaunchObserver: Any?
  private var inputMonitor: Timer?
  private var inputActive = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    Self.refreshDockIcon()
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleReopen),
      forEventClass: kCoreEventClass,
      andEventID: kAEReopenApplication
    )
  }

  static func refreshDockIcon() {
    if let iconURL = Bundle.main.url(forResource: "Maccelerate-Glass", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      NSApp.applicationIconImage = icon
    }
  }

  @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    preferencesWindowController.present()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    guard stopDuplicateInstances() else { return }
    updater.start()
    let storedGestureSpeed = UserDefaults.standard.double(forKey: "gestureSpeed")
    let speed = SwitchingSpeedPreset.fromStoredVelocity(storedGestureSpeed)
    if storedGestureSpeed != speed.velocity {
      UserDefaults.standard.set(speed.velocity, forKey: "gestureSpeed")
    }
    iss_set_gesture_speed(speed.velocity)
    StatisticsStore.shared.start()
    iss_set_switch_callback { newSpaceIndex in
      DispatchQueue.main.async {
        OSDWindow.shared.show(message: "\(newSpaceIndex + 1)")
      }
    }

    ensureAccessibilityPermission()

    if UserDefaults.standard.bool(forKey: "swipeOverride") {
      iss_set_swipe_override(true)
    }

    if UserDefaults.standard.object(forKey: "overlayDetectionEnabled") as? Bool ?? true {
      iss_set_overlay_detection_enabled(true)
    }

    setupMainMenu()
    menuBarController.delegate = self
    menuBarController.setup()
    bindHotkeys()
    observeSpaceChanges()
    observeAppActivation()
    observeAppLaunches()
    refreshSpaceInfo()
    reconcileInputConnection()
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.reconcileInputConnection() }
    }
    inputMonitor = timer
    RunLoop.main.add(timer, forMode: .common)

  }

  func applicationWillTerminate(_ notification: Notification) {
    inputMonitor?.invalidate()
    inputMonitor = nil
    HotKeyManager.shared.unregisterAll()
    StatisticsStore.shared.stop()
    iss_set_switch_callback(nil)
    iss_destroy()
    stopObservingSpaceChanges()
    stopObservingAppActivation()
    stopObservingAppLaunches()
  }

  func applicationDidHide(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationDidUnhide(_ notification: Notification) {
    if preferencesWindowController.window?.isVisible == true {
      NSApp.setActivationPolicy(.regular)
    }
  }

  private func reconcileInputConnection() {
    let allowed = iss_has_event_access()
    if !allowed && inputActive { iss_suspend_for_permission_change() }
    let active = allowed && !iss_input_requires_restart() && iss_init()
    guard active != inputActive else { return }
    inputActive = active
    if active {
      reregisterAllHotkeys()
    } else {
      HotKeyManager.shared.unregisterAll()
      iss_set_overlay_hotkey(ISSOverlayModeMissionControl, 0, 0, false)
      iss_set_overlay_hotkey(ISSOverlayModeAppExpose, 0, 0, false)
    }
    NotificationCenter.default.post(
      name: Notification.Name("MaccelerateInputConnectionChanged"), object: nil)
  }

  // Launching the app directly from a mounted DMG and then from /Applications
  // creates two independent event taps. Both would post a Cmd-Tab gesture.
  // Prefer the installed copy; among copies at the same location, keep the
  // earlier process. Both sides of a simultaneous launch then pick one winner.
  private func stopDuplicateInstances() -> Bool {
    guard let bundleID = Bundle.main.bundleIdentifier else { return true }
    let installedPath = "/Applications/Maccelerate.app"
    let thisIsInstalled = Bundle.main.bundleURL.standardizedFileURL.path == installedPath
    let thisPID = ProcessInfo.processInfo.processIdentifier

    for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    where other.processIdentifier != thisPID {
      let otherIsInstalled = other.bundleURL?.standardizedFileURL.path == installedPath
      let keepOther = (otherIsInstalled && !thisIsInstalled)
        || (otherIsInstalled == thisIsInstalled && other.processIdentifier < thisPID)
      if keepOther {
        print("Maccelerate is already running; leaving the existing instance active")
        NSApp.terminate(nil)
        return false
      }

      print("Closing another Maccelerate instance before enabling the event tap")
      guard other.terminate() else {
        NSApp.terminate(nil)
        return false
      }
      let deadline = Date().addingTimeInterval(1.0)
      while !other.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
      if !other.isTerminated {
        NSApp.terminate(nil)
        return false
      }
    }
    return true
  }

  private func ensureAccessibilityPermission() {
    guard !AXIsProcessTrusted() else { return }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu(title: Constants.appName)
    appMenuItem.submenu = appMenu

    let aboutItem = NSMenuItem(
      title: "About", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    appMenu.addItem(aboutItem)

    appMenu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    appMenu.addItem(preferencesItem)

    let updateItem = NSMenuItem(title: "Check for Updates…",
      action: #selector(UpdaterManager.checkForUpdates(_:)), keyEquivalent: "")
    updateItem.target = updater
    appMenu.addItem(updateItem)
    updater.$canCheckForUpdates.sink { [weak updateItem] available in
      updateItem?.isEnabled = available
    }.store(in: &cancellables)
    appMenu.autoenablesItems = false

    appMenu.addItem(NSMenuItem.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(servicesItem)

    appMenu.addItem(NSMenuItem.separator())

    let hideItem = NSMenuItem(
      title: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    hideItem.target = NSApp
    appMenu.addItem(hideItem)

    let hideOthersItem = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    hideOthersItem.target = NSApp
    appMenu.addItem(hideOthersItem)

    let showAllItem = NSMenuItem(
      title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    showAllItem.target = NSApp
    appMenu.addItem(showAllItem)

    appMenu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quitItem.target = NSApp
    appMenu.addItem(quitItem)

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)

    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu

    let closeItem = NSMenuItem(
      title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func openPreferences(_ sender: Any?) {
    preferencesWindowController.present()
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: NSAttributedString(
        string: "Based on InstantSpaceSwitcher by jurplel (MIT). Original Maccelerate contributions: MIT License. Full licenses and attribution are included in the app bundle.")
    ])
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  private func bindHotkeys() {
    hotkeyStore.configurationDidChange.sink { [weak self] in
      self?.scheduleHotkeyRefresh()
    }.store(in: &cancellables)
    reregisterAllHotkeys()
  }

  private func scheduleHotkeyRefresh() {
    hotkeyRefresh?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.reregisterAllHotkeys()
    }
    hotkeyRefresh = work
    DispatchQueue.main.async(execute: work)
  }

  func reregisterAllHotkeys() {
    hotkeyRefresh?.cancel()
    hotkeyRefresh = nil
    // Remove the old set first: a reset can swap two previously assigned keys.
    HotKeyManager.shared.unregisterAll()
    iss_set_overlay_hotkey(ISSOverlayModeMissionControl, 0, 0, false)
    iss_set_overlay_hotkey(ISSOverlayModeAppExpose, 0, 0, false)
    guard inputActive && iss_is_active() else { return }
    for identifier in HotkeyIdentifier.allCases {
      registerHotkey(for: identifier, combination: hotkeyStore.combination(for: identifier))
    }
  }

  private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
    menuBarController.applyHotkey(combination, to: identifier)

    if let overlayMode = overlayMode(for: identifier) {
      // Carbon turns a global shortcut into a new process-generated event.
      // macOS 27 rejects that provenance for Mission Control/App Exposé, so
      // these two shortcuts are translated in-place by ISS's physical tap.
      HotKeyManager.shared.unregister(identifier: identifier)
      iss_set_overlay_hotkey(
        overlayMode, combination.keyCode, combination.cgEventFlagsRawValue,
        hotkeyStore.isEnabled(identifier))
      return
    }

    guard hotkeyStore.isEnabled(identifier) else {
      HotKeyManager.shared.unregister(identifier: identifier)
      return
    }

    HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
      guard let self else { return }
      switch identifier {
      case .left:
        self.performSpaceSwitch(ISSDirectionLeft)
      case .right:
        self.performSpaceSwitch(ISSDirectionRight)
      case .missionControl, .appExpose:
        break
      case .space1:
        self.performSpaceSwitchToIndex(0)
      case .space2:
        self.performSpaceSwitchToIndex(1)
      case .space3:
        self.performSpaceSwitchToIndex(2)
      case .space4:
        self.performSpaceSwitchToIndex(3)
      case .space5:
        self.performSpaceSwitchToIndex(4)
      case .space6:
        self.performSpaceSwitchToIndex(5)
      case .space7:
        self.performSpaceSwitchToIndex(6)
      case .space8:
        self.performSpaceSwitchToIndex(7)
      case .space9:
        self.performSpaceSwitchToIndex(8)
      case .space10:
        self.performSpaceSwitchToIndex(9)
      case .lastSpace:
        self.performSpaceLastSpace()
      }
    }
  }

  private func overlayMode(for identifier: HotkeyIdentifier) -> ISSOverlayMode? {
    switch identifier {
    case .missionControl: return ISSOverlayModeMissionControl
    case .appExpose: return ISSOverlayModeAppExpose
    default: return nil
    }
  }

  private func performOverlay(_ mode: ISSOverlayMode, sourceEvent: NSEvent?) {
    if iss_take_overlay_menu_triggered() {
      return
    }
    guard let cgEvent = sourceEvent?.cgEvent,
      iss_trigger_overlay_from_event(mode, cgEvent)
    else {
      NSSound.beep()
      return
    }
  }

  private static let switchCompletion: ISSSwitchCompletion = { _, result in
    DispatchQueue.main.async {
      guard let delegate = NSApp.delegate as? AppDelegate else { return }
      switch result {
      case ISSSwitchResultInvalidTarget, ISSSwitchResultPostFailed, ISSSwitchResultTimedOut:
        NSSound.beep()
      default:
        break
      }
      delegate.refreshSpaceInfo()
      delegate.menuBarController.scheduleRefresh(after: 0.1)
    }
  }

  private func performSpaceSwitch(_ direction: ISSDirection) {
    if iss_uses_async_switching() {
      if iss_request_switch(direction, ISSSwitchSourceExplicit, Self.switchCompletion) == 0 {
        NSSound.beep()
      }
      return
    }
    if !iss_switch(direction) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceSwitchToIndex(_ index: UInt32) {
    if iss_uses_async_switching() {
      if iss_request_switch_to_index(index, ISSSwitchSourceExplicit, Self.switchCompletion) == 0 {
        NSSound.beep()
      }
      return
    }
    if !iss_switch_to_index(index) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceLastSpace() {
    guard let lastSpaceIndex, lastSpaceIndex != currentSpaceIndex else {
      NSSound.beep()
      return
    }

    performSpaceSwitchToIndex(lastSpaceIndex)
  }

  private func refreshSpaceInfo() {
    var info = ISSSpaceInfo()
    if iss_get_menubar_space_info(&info) {
      if currentSpaceIndex != info.currentIndex {
        lastSpaceIndex = currentSpaceIndex
        currentSpaceIndex = info.currentIndex
      }

      menuBarController.updateWithSpaceInfo(info)
    } else {
      menuBarController.updateWithSpaceInfo(nil)
    }
  }

  private func observeSpaceChanges() {
    stopObservingSpaceChanges()
    spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshSpaceInfo()
        iss_reset_predictions()
        self.menuBarController.scheduleRefresh(after: 0.2)
      }
    }
  }

  private func stopObservingSpaceChanges() {
    if let observer = spaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      spaceChangeObserver = nil
    }
  }

  private func observeAppActivation() {
    stopObservingAppActivation()
    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard self != nil else { return }
      if UserDefaults.standard.object(forKey: "accelerateCmdTab") as? Bool ?? true,
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      {
        let pid = application.processIdentifier
        let follow: @Sendable () -> Void = {
          if iss_uses_async_switching() {
            _ = iss_request_follow_cmd_tab_application(pid, nil)
          } else {
            _ = iss_follow_cmd_tab_application(pid)
          }
        }
        if Thread.isMainThread {
          follow()
        } else {
          DispatchQueue.main.async(execute: follow)
        }
      }
      Task { @MainActor [weak self] in
        self?.menuBarController.scheduleRefresh(after: 0.1)
      }
    }
  }

  private func stopObservingAppActivation() {
    if let observer = appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appActivationObserver = nil
    }
  }

  private func observeAppLaunches() {
    appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
        application.bundleIdentifier == Bundle.main.bundleIdentifier,
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
      else { return }
      Task { @MainActor [weak self] in
        _ = self?.stopDuplicateInstances()
      }
    }
  }

  private func stopObservingAppLaunches() {
    if let observer = appLaunchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appLaunchObserver = nil
    }
  }

}

extension AppDelegate: MenuBarControllerDelegate {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionLeft)
  }

  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionRight)
  }

  func menuBarController(
    _ controller: MenuBarController, didRequestOverlay mode: ISSOverlayMode,
    sourceEvent: NSEvent?
  ) {
    performOverlay(mode, sourceEvent: sourceEvent)
  }

  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
    preferencesWindowController.present()
  }

  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32
  ) {
    if iss_uses_async_switching() {
      performSpaceSwitchToIndex(index)
      return
    }
    if !iss_switch_to_index(index) {
      NSSound.beep()
    }
    controller.scheduleRefresh(after: 0.25)
  }

  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController) {
    refreshSpaceInfo()
  }
}
