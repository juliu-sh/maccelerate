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
      alphaValue = isEnabled ? 1.0 : SettingsStyle.dimmed
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
  /// Recording needs focus, but a click shows no ring; Tab does.
  private var focusedByClick = false

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
      invalidateIntrinsicContentSize()
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?
  var onRecordingCancelled: (() -> Void)?

  private var isActive: Bool { isEnabled && !isInsideClosedGate }
  override var acceptsFirstResponder: Bool { isActive }
  override var canBecomeKeyView: Bool { isActive }
  override func becomeFirstResponder() -> Bool { noteFocusRingMaskChanged(); return true }
  override func resignFirstResponder() -> Bool {
    focusedByClick = false
    noteFocusRingMaskChanged()
    return true
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func accessibilityRole() -> NSAccessibility.Role? { .button }
  override func isAccessibilityElement() -> Bool { true }
  override func isAccessibilityEnabled() -> Bool { isActive }
  override func accessibilityValue() -> Any? {
    isRecording ? "Recording. Press a key combination, or Escape to cancel." : currentShortcut?.displayString
  }
  override func accessibilityPerformPress() -> Bool {
    guard isActive else { return false }
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

  /// Wide enough for four keycaps; a fifth widens the field.
  override var intrinsicContentSize: NSSize {
    NSSize(width: max(124, capWidths.reduce(4) { $0 + $1.width + 3 }), height: 26)
  }

  private static let capFont = NSFont.systemFont(ofSize: 12, weight: .medium)

  private var capWidths: [(key: String, width: CGFloat)] {
    guard let shortcut = currentShortcut?.displayString else { return [] }
    return Self.keys(in: shortcut).map { key in
      (key, max(26, (key as NSString).size(withAttributes: [.font: Self.capFont]).width + 8))
    }
  }
  // A click focuses the field to record; the ring is only for keyboard navigation.
  override var focusRingType: NSFocusRingType {
    get { NSApp.isFullKeyboardAccessEnabled && !focusedByClick ? .default : .none }
    set {}
  }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: SettingsStyle.pillRadius, yRadius: SettingsStyle.pillRadius).fill()
  }

  /// ⌃⌥← becomes three caps; a named key such as F1 stays in one.
  static func keys(in shortcut: String) -> [String] {
    let modifiers = shortcut.prefix { "⌃⌥⇧⌘".contains($0) }
    return modifiers.map(String.init) + [String(shortcut.dropFirst(modifiers.count))]
  }

  override func draw(_ dirtyRect: NSRect) {
    let field = NSBezierPath(roundedRect: bounds, xRadius: SettingsStyle.pillRadius,
                             yRadius: SettingsStyle.pillRadius)
    if isRecording {
      SettingsStyle.switchOn.withAlphaComponent(0.14).setFill()
      field.fill()
      draw("Type shortcut…", size: 12, weight: .regular, centeredIn: bounds)
      return
    }
    if hovered && isEnabled {
      SettingsStyle.track.withAlphaComponent(0.6).setFill()
      field.fill()
    }
    guard currentShortcut != nil else {
      draw("Click to record", size: 12, weight: .regular, centeredIn: bounds)
      return
    }
    // Keycaps right-aligned, so they line up from row to row.
    let caps = capWidths
    var x = bounds.maxX - 2 - caps.reduce(0) { $0 + $1.width } - CGFloat(caps.count - 1) * 3
    for (key, width) in caps {
      let cap = NSRect(x: x, y: bounds.midY - 11, width: width, height: 22)
      NSGraphicsContext.saveGraphicsState()
      SettingsStyle.shadow(SettingsStyle.keycapEdge, blur: 0, y: -1).set()
      SettingsStyle.track.setFill()
      NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5).fill()
      NSGraphicsContext.restoreGraphicsState()
      draw(key, size: 12, weight: .medium, centeredIn: cap)
      x += width + 3
    }
  }

  private func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, centeredIn rect: NSRect) {
    let string = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: SettingsStyle.label,
    ])
    let measured = string.size()
    string.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
  }

  override func mouseDown(with event: NSEvent) {
    focusedByClick = true
    noteFocusRingMaskChanged()
    beginRecording()
  }

  private func beginRecording() {
    guard isActive else { return }
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
