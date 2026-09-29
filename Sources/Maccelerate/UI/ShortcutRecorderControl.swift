import AppKit
import Carbon

final class ShortcutRecorderControl: NSView {
  private static weak var activeRecorder: ShortcutRecorderControl?

  static func cancelActiveRecording() {
    activeRecorder?.isRecording = false
  }

  var isEnabled = true {
    didSet {
      needsDisplay = true
      alphaValue = isEnabled ? 1.0 : 0.5
    }
  }

  var isRecording = false {
    didSet {
      guard oldValue != isRecording else { return }
      needsDisplay = true
      if isRecording {
        keyPressed = false
        HotKeyManager.shared.unregisterAll()
        startEventTapRecording()
        Self.activeRecorder = self
      } else {
        stopEventTapRecording()
        if Self.activeRecorder === self {
          Self.activeRecorder = nil
        }
        // Re-register all hotkeys after recording ends
        if let appDelegate = NSApp.delegate as? AppDelegate {
          appDelegate.reregisterAllHotkeys()
        }
      }
    }
  }

  private var keyPressed = false

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?
  var onRecordingCancelled: (() -> Void)?

  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled }
  override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
  override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

  override func accessibilityRole() -> NSAccessibility.Role? { .button }
  override func isAccessibilityElement() -> Bool { true }
  override func isAccessibilityEnabled() -> Bool { isEnabled }
  override func accessibilityValue() -> Any? {
    isRecording ? "Recording. Press a key combination, or Escape to cancel." : currentShortcut?.displayString
  }
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    beginRecording()
    return true
  }
  override func keyDown(with event: NSEvent) {
    if isRecording { handleKeyEvent(event); return }
    if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
      beginRecording()
    } else { super.keyDown(with: event) }
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil && isRecording { isRecording = false }
    super.viewWillMove(toWindow: newWindow)
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  private var hovered = false
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

  private func startEventTapRecording() {
    GlobalEventTapRecorder.shared.startRecording(
      onKeyPress: { [weak self] event in
        self?.handleKeyEvent(event)
      },
      onMouseClick: { [weak self] in
        self?.isRecording = false
      }
    )
  }

  private func stopEventTapRecording() {
    GlobalEventTapRecorder.shared.stopRecording()
  }

  private func handleKeyEvent(_ event: NSEvent) {
    // Ignore additional key presses after first key
    guard !keyPressed else {
      NSSound.beep()
      return
    }

    keyPressed = true

    // Handle escape
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      onRecordingCancelled?()
      return
    }

    // Try to create combination
    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      NSSound.beep()
      keyPressed = false
      return
    }

    isRecording = false
    onRecordingComplete?(combination)
    // Hotkeys will be re-registered when store updates
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw background
    if isRecording {
      SettingsDesign.accent.withAlphaComponent(0.18).setFill()
    } else {
      (hovered && isEnabled ? SettingsDesign.inset : NSColor.controlBackgroundColor).setFill()
    }

    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
    path.fill()

    // Draw border
    let focused = window?.firstResponder === self
    (isRecording || focused ? SettingsDesign.accent : NSColor.separatorColor.withAlphaComponent(0.5)).setStroke()
    path.lineWidth = focused ? 2 : 1
    path.stroke()

    // Draw text
    let text = isRecording ? "Type shortcut…" : (currentShortcut?.displayString ?? "Click to record")
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
      .foregroundColor: NSColor.labelColor,
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
      x: (bounds.width - textSize.width) / 2,
      y: (bounds.height - textSize.height) / 2,
      width: textSize.width,
      height: textSize.height
    )

    text.draw(in: textRect, withAttributes: attributes)
  }

  override func mouseDown(with event: NSEvent) { beginRecording() }

  private func beginRecording() {
    guard isEnabled else { return }
    window?.makeFirstResponder(self)
    
    // Check accessibility permissions before starting recording
    if !AXIsProcessTrusted() {
      showAccessibilityAlert()
      return
    }

    // Stop any other active recorder
    if let activeRecorder = Self.activeRecorder, activeRecorder !== self {
      activeRecorder.isRecording = false
    }

    if !isRecording {
      isRecording = true
    }
  }

  private func showAccessibilityAlert() {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText =
      "\(Constants.appName) needs Accessibility permissions to record keyboard shortcuts.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
