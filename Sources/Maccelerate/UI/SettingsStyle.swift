import AppKit
import Carbon

/// Colors and measures of the settings window, the menu bar panel and the Space indicator.
enum SettingsStyle {
  static let canvas = color(hex(0xF7F8FA), hex(0x1C1D20))
  static let card = color(hex(0xFFFFFF), hex(0x28292D))
  static let cardRing = color(hex(0x1B2F55, 0.14), hex(0xFFFFFF, 0.09))
  static let cardShadow = color(hex(0x1B2F55, 0.09), hex(0x000000, 0.28))
  static let divider = color(hex(0xEEF0F3), hex(0xFFFFFF, 0.07))
  static let track = color(hex(0xEEF0F3), hex(0xFFFFFF, 0.08))
  static let pill = color(hex(0xFFFFFF), hex(0x4A4B50))
  static let pillShadow = color(hex(0x000000, 0.10), hex(0x000000, 0.30))
  static let label = color(hex(0x1C1916), hex(0xF2F2F3))
  static let segmentOff = color(hex(0x6B7078), hex(0xA3A6AD))
  static let secondary = color(hex(0x8A8F98), hex(0x8E9198))
  static let switchOn = NSColor.systemBlue
  static let switchOff = color(hex(0xD5D8DE), hex(0x4A4B50))
  static let hudSurface = color(hex(0xFFFFFF), hex(0x38393E))
  static let hudShadow = color(hex(0x1B2F55), hex(0x000000))
  static let keycapEdge = color(hex(0xD5D9E0), hex(0x000000, 0.45))
  static let chip = color(hex(0xEEF0F3), hex(0xFFFFFF, 0.08))
  /// Fast, Faster, Instant: one ordered hue, checked with the dataviz ordinal validator.
  static let speedSteps = [color(hex(0x76B0FF), hex(0x3A6EB5)), color(hex(0x3B8EF8), hex(0x2E8CF5)),
                           color(hex(0x0A66DC), hex(0x8CC4FF))]

  // Measured from .fin-stage-panel, the reference panel. Plain circular corners on purpose:
  // the continuous curve reads tighter and more angular at these sizes.
  static let cardRadius: CGFloat = 18
  static let trackRadius: CGFloat = 9
  static let pillRadius: CGFloat = 7
  static let padding: CGFloat = 18
  static let cardGap: CGFloat = 18
  static let dimmed: CGFloat = 0.4

  private static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
  }

  private static func color(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
  }

  // AppKit ignores shadows set directly on a view's backing layer.
  static func shadow(_ color: NSColor, blur: CGFloat, y: CGFloat) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    return shadow
  }

  static func row(_ title: String, note: String? = nil, control: NSView) -> NSView {
    row(title, noteLabel: note.map { SettingsDesign.text($0, size: 11, color: secondary) }, control: control)
  }

  /// For a note that changes later.
  static func row(_ title: String, noteLabel note: NSTextField?, control: NSView) -> NSView {
    let texts = SettingsDesign.stack([SettingsDesign.text(title, color: label)], spacing: 2)
    if let note { texts.addArrangedSubview(note) }
    let row = SettingsDesign.stack([texts, NSView(), control], vertical: false, spacing: 12)
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: note == nil ? 38 : 48).isActive = true
    return row
  }

  static func metric(_ title: String, value: String, note: String? = nil, dot: NSColor? = nil) -> NSView {
    let name = SettingsDesign.text(title, size: 11, color: secondary)
    let head: NSView
    if let dot {
      let mark = SettingsFill(dot, radius: 4)
      mark.widthAnchor.constraint(equalToConstant: 8).isActive = true
      mark.heightAnchor.constraint(equalToConstant: 8).isActive = true
      head = SettingsDesign.stack([mark, name], vertical: false, spacing: 6)
    } else {
      head = name
    }
    let number = SettingsDesign.text(value, size: 15, weight: .semibold, color: label)
    let cell = SettingsDesign.stack([head, number], spacing: 3)
    if let note { cell.addArrangedSubview(SettingsDesign.text(note, size: 11, color: secondary)) }
    return cell
  }

  static func columns(_ views: [NSView]) -> NSStackView {
    let columns = SettingsDesign.stack(views, vertical: false, spacing: 12)
    columns.alignment = .top
    columns.distribution = .fillEqually
    return columns
  }
}

/// Keeps layer colors in step with the window's appearance.
class StyledLayerView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    translatesAutoresizingMaskIntoConstraints = false
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func applyStyle() {}
  var viewShadow: NSShadow? { nil }

  // Assigning a shadow invalidates layout, so it stays out of applyStyle.
  private func updateShadow() {
    effectiveAppearance.performAsCurrentDrawingAppearance { shadow = viewShadow }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateShadow()
  }

  final func styled(animated: Bool = false, _ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(!animated)
    CATransaction.setAnimationDuration(0.16)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
    effectiveAppearance.performAsCurrentDrawingAppearance(body)
    CATransaction.commit()
  }

  override func layout() { super.layout(); applyStyle() }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateShadow()
    applyStyle()
  }
}

/// Holds settings that depend on a switch: they stay visible, dimmed and out of reach while it is off.
final class SettingsGate: NSView {
  var isOpen = true {
    didSet {
      alphaValue = isOpen ? 1 : SettingsStyle.dimmed
      // Keyboard focus must not stay on a control that just became unavailable.
      if !isOpen, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: self) {
        window?.makeFirstResponder(nil)
      }
    }
  }

  init(_ content: NSView) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    SettingsDesign.pin(content, to: self)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { isOpen ? super.hitTest(point) : nil }
}

extension NSView {
  /// True while a closed gate holds the view: keyboard and VoiceOver leave it alone as well.
  var isInsideClosedGate: Bool {
    var view = superview
    while let current = view {
      if let gate = current as? SettingsGate, !gate.isOpen { return true }
      view = current.superview
    }
    return false
  }
}

final class SettingsFill: StyledLayerView {
  private let color: NSColor
  private let radius: CGFloat
  private let ring: NSColor?
  init(_ color: NSColor, radius: CGFloat = 0, ring: NSColor? = nil) {
    self.color = color
    self.radius = radius
    self.ring = ring
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func applyStyle() {
    styled {
      layer?.backgroundColor = color.cgColor
      layer?.cornerRadius = radius
      layer?.borderWidth = ring == nil ? 0 : 0.5
      layer?.borderColor = ring?.cgColor
    }
  }
}

final class SettingsChip: StyledLayerView {
  init(_ title: String) {
    super.init(frame: .zero)
    let label = SettingsDesign.text(title, size: 11, weight: .medium, color: SettingsStyle.segmentOff)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 20),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func applyStyle() {
    styled {
      layer?.backgroundColor = SettingsStyle.chip.cgColor
      layer?.cornerRadius = 10
    }
  }
}

/// Focus, keyboard and VoiceOver behavior shared by the custom controls.
/// Like native controls, they take keyboard focus only with Full Keyboard Access.
class SettingsControl: StyledLayerView {
  var isEnabled = true
  /// Enabled and not held by a closed gate.
  var isActive: Bool { isEnabled && !isInsideClosedGate }
  var focusRadius: CGFloat { SettingsStyle.pillRadius }

  override func isAccessibilityEnabled() -> Bool { isActive }
  // Like AppKit's buttons, a click never takes focus; the ring follows Tab only.
  override var acceptsFirstResponder: Bool {
    canBecomeKeyView && NSApp.currentEvent?.type != .leftMouseDown
  }
  override var canBecomeKeyView: Bool { isActive && NSApp.isFullKeyboardAccessEnabled }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: focusRadius, yRadius: focusRadius).fill()
  }

  override func keyDown(with event: NSEvent) {
    guard isActive else { return super.keyDown(with: event) }
    switch Int(event.keyCode) {
    case kVK_Space, kVK_Return: activate()
    case kVK_LeftArrow, kVK_UpArrow: step(-1)
    case kVK_RightArrow, kVK_DownArrow: step(1)
    default: super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isActive else { return false }
    activate()
    return true
  }

  /// Space, Return and VoiceOver's press.
  func activate() {}
  /// Arrow keys.
  func step(_ delta: Int) {}
}

/// Quiet button in the segmented track's tint, so no native bezel sits on the white card.
final class SettingsButton: SettingsControl {
  private let action: () -> Void
  private let label: NSTextField
  override var isEnabled: Bool { didSet { label.alphaValue = isEnabled ? 1 : SettingsStyle.dimmed } }

  init(_ title: String, action: @escaping () -> Void) {
    self.action = action
    label = SettingsDesign.text(title, color: SettingsStyle.label)
    super.init(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    addSubview(label)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 28),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
    ])
    let hug = widthAnchor.constraint(equalTo: label.widthAnchor, constant: 24)
    hug.priority = .defaultHigh
    hug.isActive = true
    setContentHuggingPriority(.required, for: .horizontal)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(title)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    alphaValue = 0.6
  }
  override func mouseUp(with event: NSEvent) {
    alphaValue = 1
    guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    action()
  }
  override func activate() { action() }

  override func applyStyle() {
    styled {
      layer?.backgroundColor = SettingsStyle.track.cgColor
      layer?.cornerRadius = SettingsStyle.pillRadius
    }
  }
}

/// White surface above the canvas, with a hairline ring and a soft shadow.
final class SettingsCard: StyledLayerView {
  let content = SettingsDesign.stack(spacing: 0)

  init(title: String, accessory: NSView? = nil) {
    super.init(frame: .zero)
    let inner = SettingsDesign.stack([content], spacing: 0)
    addSubview(inner)
    NSLayoutConstraint.activate([
      inner.topAnchor.constraint(equalTo: topAnchor, constant: SettingsStyle.padding),
      inner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
      inner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsStyle.padding),
      inner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsStyle.padding),
      content.widthAnchor.constraint(equalTo: inner.widthAnchor),
    ])
    let name = SettingsDesign.text(title, weight: .semibold, color: SettingsStyle.label)
    let heading = accessory.map {
      SettingsDesign.stack([name, NSView(), $0], vertical: false, spacing: 8) as NSView
    } ?? name
    add(heading, spacingAfter: 10)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var viewShadow: NSShadow? { SettingsStyle.shadow(SettingsStyle.cardShadow, blur: 16, y: -7) }

  func add(_ view: NSView, spacingAfter: CGFloat = 0) {
    content.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    content.setCustomSpacing(spacingAfter, after: view)
  }

  func divider() -> NSView {
    let line = SettingsFill(SettingsStyle.divider)
    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return line
  }

  func addRows(_ rows: [NSView]) {
    for row in rows {
      add(divider())
      add(row)
    }
  }

  func addGap(_ height: CGFloat) {
    let gap = NSView()
    gap.heightAnchor.constraint(equalToConstant: height).isActive = true
    add(gap)
  }

  override func applyStyle() {
    styled {
      guard let layer else { return }
      layer.backgroundColor = SettingsStyle.card.cgColor
      layer.cornerRadius = SettingsStyle.cardRadius
      layer.borderWidth = 0.5
      layer.borderColor = SettingsStyle.cardRing.cgColor
    }
  }
}

/// 28 × 17 switch: blue when on.
final class SettingsSwitch: SettingsControl {
  private let track = CALayer()
  private let knob = CALayer()
  /// Setting it from code updates the look without calling onChange.
  var isOn: Bool {
    didSet {
      setAccessibilityValue(isOn)
      updateState(animated: false)
    }
  }
  var onChange: ((Bool) -> Void)?
  override var focusRadius: CGFloat { bounds.height / 2 }
  override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : SettingsStyle.dimmed } }

  init(on: Bool = false, label: String) {
    isOn = on
    super.init(frame: .zero)
    layer?.addSublayer(track)
    track.addSublayer(knob)
    setAccessibilityElement(true)
    setAccessibilityRole(.checkBox)
    setAccessibilityLabel(label)
    setAccessibilityValue(on)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 17) }

  override func mouseDown(with event: NSEvent) { if isEnabled { activate() } }
  override func activate() {
    isOn.toggle()
    updateState(animated: true)
    onChange?(isOn)
  }

  override func applyStyle() { updateState(animated: false) }

  private func updateState(animated: Bool) {
    styled(animated: animated) {
      track.frame = bounds
      track.cornerRadius = bounds.height / 2
      track.backgroundColor = (isOn ? SettingsStyle.switchOn : SettingsStyle.switchOff).cgColor
      knob.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
      knob.cornerRadius = 6.5
      knob.backgroundColor = NSColor.white.cgColor
      knob.position = CGPoint(x: isOn ? bounds.width - 8.5 : 8.5, y: bounds.midY)
    }
  }
}

/// Three sizes carry the hierarchy: page tabs, controls in a card, controls in the menu panel.
struct SettingsSegmentSize {
  let height, inset, fontSize, trackRadius, pillRadius: CGFloat
  static let tabs = Self(height: 38, inset: 4, fontSize: 13, trackRadius: 11, pillRadius: 7)
  static let inline = Self(height: 33, inset: 3, fontSize: 12.5, trackRadius: 8, pillRadius: 6)
  static let compact = Self(height: 30, inset: 3, fontSize: 12, trackRadius: 8, pillRadius: 6)
}

/// Tinted track with a white pill that slides to the selected segment.
/// A selection of -1 shows no pill, for a value that matches no segment.
final class SettingsSegmented: SettingsControl {
  private let pill: SettingsPill
  private let size: SettingsSegmentSize
  private let titles: [NSTextField]
  private lazy var segments = titles.indices.map { SettingsSegmentElement(control: self, index: $0) }
  /// Setting it from code moves the pill without calling onChange.
  var selected: Int {
    didSet {
      guard selected != oldValue else { return }
      pill.isHidden = !titles.indices.contains(selected)
      if !isChoosing { needsLayout = true }
      applyStyle()
    }
  }
  var onChange: ((Int) -> Void)?
  override var focusRadius: CGFloat { size.trackRadius }
  private var isChoosing = false
  override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : SettingsStyle.dimmed } }

  private var inset: CGFloat { size.inset }

  init(titles: [String], selected: Int, size: SettingsSegmentSize = .inline, label: String) {
    self.size = size
    pill = SettingsPill(radius: size.pillRadius)
    self.titles = titles.map { title in
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: size.fontSize)
      label.alignment = .center
      return label
    }
    self.selected = selected
    super.init(frame: .zero)
    pill.translatesAutoresizingMaskIntoConstraints = true
    pill.isHidden = !self.titles.indices.contains(selected)
    addSubview(pill)
    self.titles.forEach(addSubview)
    heightAnchor.constraint(equalToConstant: size.height).isActive = true
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel(label)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // The labels sit on top; the whole track is one click target.
  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  private var segmentWidth: CGFloat { (bounds.width - inset * 2) / CGFloat(titles.count) }

  fileprivate func segmentFrame(_ index: Int) -> NSRect {
    NSRect(x: inset + CGFloat(index) * segmentWidth, y: inset,
           width: segmentWidth, height: bounds.height - inset * 2)
  }

  fileprivate func title(_ index: Int) -> String { titles[index].stringValue }

  override func layout() {
    super.layout()
    if titles.indices.contains(selected) { pill.frame = segmentFrame(selected) }
    for (index, label) in titles.enumerated() {
      let height = label.intrinsicContentSize.height
      label.frame = NSRect(x: inset + CGFloat(index) * segmentWidth, y: (bounds.height - height) / 2,
                           width: segmentWidth, height: height)
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    let x = convert(event.locationInWindow, from: nil).x
    choose(min(max(Int((x - inset) / segmentWidth), 0), titles.count - 1))
  }

  override func step(_ delta: Int) {
    let start = titles.indices.contains(selected) ? selected : (delta > 0 ? -1 : titles.count)
    choose(min(max(start + delta, 0), titles.count - 1))
  }

  fileprivate func choose(_ index: Int) {
    guard index != selected, titles.indices.contains(index) else { return }
    let wasHidden = pill.isHidden
    isChoosing = !wasHidden
    selected = index
    isChoosing = false
    if wasHidden {
      pill.frame = segmentFrame(index)
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pill.animator().frame = segmentFrame(index)
      }
    }
    onChange?(index)
  }

  override func applyStyle() {
    styled {
      layer?.backgroundColor = SettingsStyle.track.cgColor
      layer?.cornerRadius = size.trackRadius
    }
    for (index, label) in titles.enumerated() {
      label.textColor = index == selected ? SettingsStyle.label : SettingsStyle.segmentOff
    }
  }

  override func accessibilityChildren() -> [Any]? { segments }
  override func accessibilityValue() -> Any? {
    titles.indices.contains(selected) ? titles[selected].stringValue : nil
  }
}

/// One VoiceOver radio button per segment.
private final class SettingsSegmentElement: NSAccessibilityElement {
  private weak var control: SettingsSegmented?
  private let index: Int

  init(control: SettingsSegmented, index: Int) {
    self.control = control
    self.index = index
    super.init()
    setAccessibilityParent(control)
    setAccessibilityRole(.radioButton)
  }

  override func accessibilityLabel() -> String? { control?.title(index) }
  override func accessibilityValue() -> Any? { control?.selected == index }
  override func isAccessibilityEnabled() -> Bool { control?.isActive ?? false }
  override func accessibilityFrameInParentSpace() -> NSRect { control?.segmentFrame(index) ?? .zero }
  override func accessibilityPerformPress() -> Bool {
    guard let control, control.isActive else { return false }
    control.choose(index)
    return true
  }
}
final class SettingsPill: StyledLayerView {
  private let radius: CGFloat
  init(radius: CGFloat) {
    self.radius = radius
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var viewShadow: NSShadow? { SettingsStyle.shadow(SettingsStyle.pillShadow, blur: 2, y: -1) }

  override func applyStyle() {
    styled {
      guard let layer else { return }
      layer.backgroundColor = SettingsStyle.pill.cgColor
      layer.cornerRadius = radius
    }
  }
}

/// Borderless symbol button, such as a row's reset arrow.
final class SettingsIconButton: SettingsControl {
  private let action: () -> Void
  private let image = NSImageView()
  override var isEnabled: Bool { didSet { image.alphaValue = isEnabled ? 1 : SettingsStyle.dimmed } }
  var symbol: String { didSet { image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) } }

  init(symbol: String, label: String, action: @escaping () -> Void) {
    self.action = action
    self.symbol = symbol
    super.init(frame: .zero)
    image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    image.contentTintColor = SettingsStyle.secondary
    image.translatesAutoresizingMaskIntoConstraints = false
    addSubview(image)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 20), heightAnchor.constraint(equalToConstant: 20),
      image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    toolTip = label
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(label)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  override func mouseDown(with event: NSEvent) { if isEnabled { image.alphaValue = 0.5 } }
  override func mouseUp(with event: NSEvent) {
    image.alphaValue = isEnabled ? 1 : SettingsStyle.dimmed
    guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    action()
  }
  override func activate() { action() }
}
