import AppKit
import ISS

/// Shared by the live HUD and the settings preview.
final class SpaceHUDView: NSView {
  private let number = SettingsDesign.text("", size: 30, weight: .semibold)
  init() {
    super.init(frame: .zero)
    number.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
    let labels = SettingsDesign.stack([
      SettingsDesign.text("Space", size: 14, weight: .semibold),
      SettingsDesign.text("Maccelerate", size: 10, color: .secondaryLabelColor),
    ], spacing: 3)
    let row = SettingsDesign.stack([SymbolTile(symbol: "rectangle.on.rectangle"), labels, NSView(), number],
                                   vertical: false, spacing: 12)
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    (dark ? NSColor(white: 0.15, alpha: 0.97) : NSColor(white: 0.97, alpha: 0.97)).setFill()
    path.fill()
    (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)).setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  func setSpace(_ value: String) {
    number.stringValue = value
    setAccessibilityLabel("Space \(value)")
  }
}

final class OSDWindow {
  static let shared = OSDWindow()
  private var window: NSWindow?
  private var hud: SpaceHUDView?
  private var hideTimer: Timer?
  private var presentationID = 0
  private init() {}

  func show(message: String) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }
    let detection = UserDefaults.standard.object(forKey: "overlayDetectionEnabled") as? Bool ?? true
    if detection && iss_is_mission_control_active() { return }
    present(message: message, duration: nil)
  }

  func showPreview() {
    let duration = Double(UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 200) / 1000
    present(message: "2", duration: duration)
  }

  private func present(message: String, duration: TimeInterval?) {
    hideTimer?.invalidate()
    presentationID += 1
    if window == nil { createWindow() }
    guard let window, let hud else { return }
    hud.setSpace(message)
    let mouse = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
      let frame = screen.visibleFrame
      window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.minY + 64))
    }
    // Cancel a previous fade before a rapid subsequent switch.
    window.contentView?.layer?.removeAllAnimations()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      window.animator().alphaValue = 1
    }
    window.orderFrontRegardless()
    let delay = duration ?? Double(UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 200) / 1000
    hideTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, delay), repeats: false) { [weak self] _ in
      self?.hide()
    }
  }

  private func createWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 214, height: 64),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    window.hasShadow = false
    let hud = SpaceHUDView()
    window.contentView = hud
    self.hud = hud
    self.window = window
  }

  private func hide() {
    let id = presentationID
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
      window?.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      guard let self, self.presentationID == id else { return }
      self.window?.orderOut(nil)
    }
  }
}
