import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
  convenience init() {
    let tabViewController = PreferencesTabViewController()
    let height = max(600, min(820, (NSScreen.main?.visibleFrame.height ?? 880) - 60))

    let panel = PreferencesPanel(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: height),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.title = "\(Constants.appName) Settings"
    tabViewController.view.frame = NSRect(x: 0, y: 0, width: 660, height: height)
    tabViewController.preferredContentSize = NSSize(width: 660, height: height)
    NSLayoutConstraint.activate([
      tabViewController.view.widthAnchor.constraint(equalToConstant: 660),
      tabViewController.view.heightAnchor.constraint(equalToConstant: height),
    ])
    panel.contentViewController = tabViewController
    panel.setContentSize(NSSize(width: 660, height: height))
    panel.contentMinSize = NSSize(width: 660, height: height)
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.center()

    self.init(window: panel)
    panel.delegate = self
  }

  func present() {
    guard let window = window else { return }

    NSApp.setActivationPolicy(.regular)
    AppDelegate.refreshDockIcon()
    NSApp.dockTile.display()
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }
}

extension PreferencesWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    // Finish closing before leaving the regular app mode. A rapid reopen keeps the Dock icon.
    DispatchQueue.main.async { [weak self] in
      guard self?.window?.isVisible == false else { return }
      NSApp.setActivationPolicy(.accessory)
      NSApp.hide(nil)
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    // Cancel any active recording when window loses focus
    ShortcutRecorderControl.cancelActiveRecording()
  }
}
