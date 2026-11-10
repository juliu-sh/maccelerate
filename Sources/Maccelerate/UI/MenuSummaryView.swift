import AppKit
import ISS

/// Full-width Space tiles for the menu bar panel; a click moves there.
final class MenuSpacePicker: SettingsControl {
  private let total: Int
  private let space: Int
  private let onSelect: (Int) -> Void
  private static let rowHeight: CGFloat = 36

  init(space: Int, total: Int, onSelect: @escaping (Int) -> Void) {
    self.space = space
    self.total = total
    self.onSelect = onSelect
    super.init(frame: .zero)
    let rows = CGFloat(SpaceIndicatorView.tileGrid(total).rows)
    heightAnchor.constraint(equalToConstant: rows * Self.rowHeight + (rows - 1) * 4).isActive = true
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel("Spaces")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private lazy var tiles = (1...max(total, 1)).map { MenuSpaceElement(picker: self, space: $0) }
  override func accessibilityChildren() -> [Any]? { tiles }
  override func accessibilityValue() -> Any? { "Space \(space) of \(total)" }

  override func draw(_ dirtyRect: NSRect) {
    SpaceIndicatorView.drawTiles(in: bounds, space: space, total: total, fontSize: 13)
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  fileprivate func frame(of target: Int) -> NSRect {
    let grid = SpaceIndicatorView.tileGrid(total)
    let width = (bounds.width - 4 * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
    let height = (bounds.height - 4 * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
    let column = (target - 1) % grid.columns, row = (target - 1) / grid.columns
    return NSRect(x: CGFloat(column) * (width + 4), y: bounds.maxY - height - CGFloat(row) * (height + 4),
                  width: width, height: height)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let target = (1...max(total, 1)).first(where: { frame(of: $0).insetBy(dx: -2, dy: -2).contains(point) })
    else { return }
    choose(target)
  }

  override func step(_ delta: Int) { choose(min(max(space + delta, 1), total)) }

  fileprivate func choose(_ target: Int) {
    guard target != space else { return }
    onSelect(target)
  }
}

private final class MenuSpaceElement: NSAccessibilityElement {
  private weak var picker: MenuSpacePicker?
  private let space: Int

  init(picker: MenuSpacePicker, space: Int) {
    self.picker = picker
    self.space = space
    super.init()
    setAccessibilityParent(picker)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel("Space \(space)")
  }

  override func accessibilityFrameInParentSpace() -> NSRect { picker?.frame(of: space) ?? .zero }
  override func accessibilityPerformPress() -> Bool {
    guard picker?.isActive == true else { return false }
    picker?.choose(space)
    return picker != nil
  }
}

/// Text row with a hover fill, in place of a native menu item.
final class MenuPanelRow: SettingsControl {
  private let action: () -> Void
  private let title: NSTextField
  private var isHovered = false { didSet { applyStyle() } }
  override var isEnabled: Bool {
    didSet {
      title.textColor = isEnabled ? SettingsStyle.label : SettingsStyle.secondary
      if !isEnabled { isHovered = false }
    }
  }

  init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
    self.action = action
    self.title = SettingsDesign.text(title, color: SettingsStyle.label)
    super.init(frame: .zero)
    let row = SettingsDesign.stack([self.title, NSView()], vertical: false, spacing: 8)
    if let shortcut {
      row.addArrangedSubview(SettingsDesign.text(shortcut, size: 12, color: SettingsStyle.secondary))
    }
    addSubview(row)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 28),
      row.centerYAnchor.constraint(equalTo: centerYAnchor),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.menuItem)
    setAccessibilityLabel(title)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self))
  }
  override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
  override func mouseExited(with event: NSEvent) { isHovered = false }
  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    if isEnabled { action() }
  }
  override func mouseDown(with event: NSEvent) {}
  override func activate() { action() }

  override func applyStyle() {
    styled {
      layer?.backgroundColor = (isHovered ? SettingsStyle.track : .clear).cgColor
      layer?.cornerRadius = SettingsStyle.pillRadius
    }
  }
}

/// Becomes key without activating Maccelerate, like a menu, so the frontmost app,
/// its windows and Stage Manager stay as they are.
final class MenuPanelWindow: NSPanel {
  var onClose: (() -> Void)?
  var keyEquivalents: [String: () -> Void] = [:]

  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onClose?() }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased(),
       let action = keyEquivalents[key] {
      action()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// Holds the panel inside transparent room and draws a shadow lighter than the system's window shadow.
final class MenuPanelBackdrop: NSView {
  static let room: CGFloat = 32
  private let radius: CGFloat
  var onClickOutside: (() -> Void)?

  init(_ surface: NSView, radius: CGFloat) {
    self.radius = radius
    super.init(frame: .zero)
    SettingsDesign.pin(surface, to: self, inset: Self.room)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isOpaque: Bool { false }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    SettingsStyle.card.setFill()
    IndicatorShadow.medium.draw(around: bounds.insetBy(dx: Self.room, dy: Self.room), radius: radius,
                                shape: .layered, in: self)
  }
  // The shadow is part of the window, so a click on it would otherwise not close the panel.
  override func mouseDown(with event: NSEvent) { onClickOutside?() }
}
