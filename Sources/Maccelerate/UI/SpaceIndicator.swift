import AppKit
import Carbon
import ISS

enum IndicatorStyle: Int, CaseIterable {
  case card, number, dots, tiles

  var title: String {
    switch self {
    case .card: return "Card"
    case .number: return "Number"
    case .dots: return "Dots"
    case .tiles: return "Tiles"
    }
  }

  /// Dots and Tiles grow with the number of Spaces; Tiles start a new row after eight.
  func size(total: Int) -> NSSize {
    switch self {
    case .card: return NSSize(width: 196, height: 60)
    case .number: return NSSize(width: 68, height: 68)
    case .dots: return NSSize(width: max(128, 76 + 13 * CGFloat(total - 1)), height: 44)
    case .tiles:
      let grid = SpaceIndicatorView.tileGrid(total)
      return NSSize(width: 10 + 34 * CGFloat(grid.columns) + 4 * CGFloat(grid.columns - 1),
                    height: 10 + 30 * CGFloat(grid.rows) + 4 * CGFloat(grid.rows - 1))
    }
  }

  /// About a quarter of the height, the proportion of the tab pill. Tiles stay concentric.
  var radius: CGFloat {
    switch self {
    case .card: return 14
    case .number: return 16
    case .dots: return 11
    case .tiles: return 11
    }
  }
}

/// Three columns, five rows. The default keeps the indicator's usual place, bottom centre.
struct IndicatorPosition: Equatable {
  static let standard = IndicatorPosition()

  static let columns = 3
  static let rows = 5
  static let all = (0..<rows).flatMap { row in
    (0..<columns).map { IndicatorPosition(column: $0, row: row) }
  }
  private static let margin: CGFloat = 64

  var column = 1
  var row = 4

  /// Index into `all`, as stored in the preferences.
  var index: Int { row * Self.columns + column }

  init(column: Int = 1, row: Int = 4) {
    self.column = column
    self.row = row
  }

  init?(index: Int) {
    guard Self.all.indices.contains(index) else { return nil }
    self = Self.all[index]
  }

  func origin(for size: NSSize, in frame: NSRect) -> NSPoint {
    let width = frame.width - size.width - Self.margin * 2
    let height = frame.height - size.height - Self.margin * 2
    return NSPoint(x: frame.minX + Self.margin + width * CGFloat(column) / CGFloat(Self.columns - 1),
                   y: frame.maxY - Self.margin - size.height - height * CGFloat(row) / CGFloat(Self.rows - 1))
  }
}

struct IndicatorShadowLayer {
  var blur: CGFloat
  var y: CGFloat
  var alpha: CGFloat
  var spread: CGFloat = 0
}

/// Where the shadow sits. Amount and shape are separate, so every level works with every shape.
enum IndicatorShadowShape: Int, CaseIterable {
  case layered, even, below

  var title: String {
    switch self {
    case .layered: return "Layered"
    case .even: return "Even"
    case .below: return "Below"
    }
  }
}

enum IndicatorShadow: Int, CaseIterable {
  case none, soft, medium, strong

  var title: String {
    switch self {
    case .none: return "None"
    case .soft: return "Soft"
    case .medium: return "Medium"
    case .strong: return "Strong"
    }
  }

  func layers(_ shape: IndicatorShadowShape) -> [IndicatorShadowLayer] {
    let blur: CGFloat, y: CGFloat, alpha: CGFloat
    switch self {
    case .none: return []
    case .soft: (blur, y, alpha) = (5, 1.5, 0.14)
    case .medium: (blur, y, alpha) = (12, 4, 0.20)
    case .strong: (blur, y, alpha) = (22, 8, 0.28)
    }
    switch shape {
    case .layered:
      // A tight contact edge, like the tab pill, under a wide faint ambient shadow.
      return [IndicatorShadowLayer(blur: blur * 1.4, y: y, alpha: alpha * 0.6),
              IndicatorShadowLayer(blur: 2, y: 1, alpha: alpha * 0.8)]
    case .even:
      return [IndicatorShadowLayer(blur: blur * 1.2, y: 0, alpha: alpha)]
    case .below:
      // Pulled in at the sides, so nothing shows above the indicator.
      return [IndicatorShadowLayer(blur: blur, y: y * 1.6, alpha: alpha * 1.2, spread: blur * 0.4)]
    }
  }

  /// Casts the shadow of a rounded surface, using the current fill color.
  func draw(around surface: NSRect, radius: CGFloat, shape: IndicatorShadowShape, in view: NSView) {
    let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    for layer in layers(shape) {
      NSGraphicsContext.saveGraphicsState()
      let color = SettingsStyle.hudShadow.withAlphaComponent(min(1, layer.alpha * (isDark ? 2.2 : 1)))
      SettingsStyle.shadow(color, blur: layer.blur, y: -layer.y).set()
      let radius = max(0, radius - layer.spread)
      NSBezierPath(roundedRect: surface.insetBy(dx: layer.spread, dy: layer.spread),
                   xRadius: radius, yRadius: radius).fill()
      NSGraphicsContext.restoreGraphicsState()
    }
  }
}

/// One view for all indicator styles, used by the on-screen window and the style picker.
/// It is larger than the indicator, because it draws the shadow itself.
final class SpaceIndicatorView: NSView {
  static let shadowRoom: CGFloat = 48
  private let style: IndicatorStyle
  var space = 2 { didSet { needsDisplay = true } }
  var total = 5 { didSet { needsDisplay = true } }
  var shadowLevel = IndicatorShadow.none { didSet { needsDisplay = true } }
  var shadowShape = IndicatorShadowShape.layered { didSet { needsDisplay = true } }
  private var face: NSRect { NSRect(origin: .zero, size: style.size(total: total)) }

  init(style: IndicatorStyle, space: Int = 2, total: Int = 5) {
    self.style = style
    self.space = space
    self.total = total
    super.init(frame: NSRect(origin: .zero, size: style.size(total: total)))
    translatesAutoresizingMaskIntoConstraints = false
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Space \(space) of \(total)")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isOpaque: Bool { false }
  override var intrinsicContentSize: NSSize {
    NSSize(width: face.width + Self.shadowRoom * 2, height: face.height + Self.shadowRoom * 2)
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let surface = face.offsetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
    SettingsStyle.hudSurface.setFill()
    shadowLevel.draw(around: surface, radius: style.radius, shape: shadowShape, in: self)
    NSBezierPath(roundedRect: surface, xRadius: style.radius, yRadius: style.radius).fill()
    // Without the border, Increase Contrast needs another edge than the shadow.
    if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
      SettingsStyle.secondary.setStroke()
      let ring = NSBezierPath(roundedRect: surface.insetBy(dx: 0.5, dy: 0.5),
                              xRadius: style.radius, yRadius: style.radius)
      ring.lineWidth = 1
      ring.stroke()
    }

    let transform = NSAffineTransform()
    transform.translateX(by: Self.shadowRoom, yBy: Self.shadowRoom)
    transform.concat()
    switch style {
    case .card: drawCard()
    case .number: draw("\(space)", size: 34, weight: .semibold, centeredIn: face)
    case .dots: drawDots()
    case .tiles: SpaceIndicatorView.drawTiles(in: face.insetBy(dx: 5, dy: 5), space: space, total: total)
    }
  }

  private func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = SettingsStyle.label,
                    centeredIn rect: NSRect) {
    let string = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ])
    let measured = string.size()
    string.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
  }

  private func drawCard() {
    let icon = NSRect(x: 12, y: face.midY - 18, width: 36, height: 36)
    NSApp.applicationIconImage.draw(in: icon)
    NSAttributedString(string: "Space", attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: SettingsStyle.label,
    ]).draw(at: NSPoint(x: 58, y: face.midY + 1))
    NSAttributedString(string: "\(space) of \(total)", attributes: [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: SettingsStyle.secondary,
    ]).draw(at: NSPoint(x: 58, y: face.midY - 15))
    draw("\(space)", size: 30, weight: .semibold,
         centeredIn: NSRect(x: face.maxX - 54, y: 0, width: 40, height: face.height))
  }

  /// Position at a glance: the current Space is the one long mark.
  private func drawDots() {
    let dot: CGFloat = 7
    let gap: CGFloat = 6
    let long: CGFloat = 18
    let width = long + CGFloat(total - 1) * (dot + gap)
    draw("\(space)", size: 15, weight: .semibold,
         centeredIn: NSRect(x: 12, y: 0, width: 18, height: face.height))
    var x = 34 + (face.width - 46 - width) / 2
    for index in 1...total {
      let current = index == space
      let rect = NSRect(x: x, y: face.midY - dot / 2, width: current ? long : dot, height: dot)
      (current ? SettingsStyle.switchOn : SettingsStyle.switchOff).setFill()
      NSBezierPath(roundedRect: rect, xRadius: dot / 2, yRadius: dot / 2).fill()
      x += rect.width + gap
    }
  }

  /// Up to eight tiles in a row; more Spaces continue in further rows.
  static func tileGrid(_ total: Int) -> (columns: Int, rows: Int) {
    let count = max(total, 1)
    let rows = (count + 7) / 8
    return ((count + rows - 1) / rows, rows)
  }

  /// Spaces as small desktops. The menu bar panel shares this drawing.
  static func drawTiles(in rect: NSRect, space: Int, total: Int, fontSize: CGFloat = 12) {
    let gap: CGFloat = 4
    let grid = tileGrid(total)
    let width = (rect.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
    let height = (rect.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
    for index in 0..<total {
      let column = index % grid.columns, row = index / grid.columns
      let tile = NSRect(x: rect.minX + CGFloat(column) * (width + gap),
                        y: rect.maxY - height - CGFloat(row) * (height + gap),
                        width: width, height: height)
      let current = index + 1 == space
      (current ? SettingsStyle.switchOn : SettingsStyle.track).setFill()
      NSBezierPath(roundedRect: tile, xRadius: 6, yRadius: 6).fill()
      let label = NSAttributedString(string: "\(index + 1)", attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: current ? .semibold : .medium),
        .foregroundColor: current ? NSColor.white : SettingsStyle.segmentOff,
      ])
      let measured = label.size()
      label.draw(at: NSPoint(x: tile.midX - measured.width / 2, y: tile.midY - measured.height / 2))
    }
  }
}

/// Picker entry: the real indicator on the stage tint, so all styles compare at true size.
final class IndicatorStyleOption: SettingsControl {
  let style: IndicatorStyle
  private let stage = SettingsRingView()
  private let hud: SpaceIndicatorView
  private let caption: NSTextField
  var onSelect: ((IndicatorStyle) -> Void)?
  var isSelected = false { didSet { updateSelection() } }

  init(style: IndicatorStyle) {
    self.style = style
    hud = SpaceIndicatorView(style: style)
    caption = SettingsDesign.text(style.title, size: 12, color: SettingsStyle.segmentOff)
    super.init(frame: .zero)
    stage.addSubview(hud)
    caption.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stage)
    addSubview(caption)
    NSLayoutConstraint.activate([
      stage.topAnchor.constraint(equalTo: topAnchor),
      stage.leadingAnchor.constraint(equalTo: leadingAnchor),
      stage.trailingAnchor.constraint(equalTo: trailingAnchor),
      stage.heightAnchor.constraint(equalToConstant: 88),
      hud.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
      hud.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
      caption.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 6),
      caption.centerXAnchor.constraint(equalTo: centerXAnchor),
      caption.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel("\(style.title) indicator")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var focusRadius: CGFloat { SettingsStyle.trackRadius }
  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  override func mouseDown(with event: NSEvent) { activate() }
  override func activate() { onSelect?(style) }
  override func accessibilityValue() -> Any? { isSelected }

  func setShadow(_ level: IndicatorShadow, shape: IndicatorShadowShape) {
    hud.shadowLevel = level
    hud.shadowShape = shape
  }

  private func updateSelection() {
    stage.isRinged = isSelected
    caption.textColor = isSelected ? SettingsStyle.label : SettingsStyle.segmentOff
  }
}

final class SettingsRingView: StyledLayerView {
  var isRinged = false { didSet { applyStyle() } }
  override func applyStyle() {
    styled {
      layer?.backgroundColor = SettingsStyle.track.cgColor
      layer?.cornerRadius = SettingsStyle.trackRadius
      layer?.masksToBounds = true
      layer?.borderWidth = isRinged ? 2 : 0
      layer?.borderColor = SettingsStyle.switchOn.cgColor
    }
  }
}

/// The screen in miniature, with the indicator's 15 places at their true positions.
final class IndicatorPositionPicker: SettingsControl {
  private let indicator = SpaceIndicator.shared
  private var hovered: IndicatorPosition? { didSet { needsDisplay = true } }
  var onSelect: (() -> Void)?
  /// One schematic for every style, drawn as Dots, so the screen stays put while choosing a style.
  private static let markSize = IndicatorStyle.dots.size(total: 1)

  /// The surrounding layout sets the height, and the places spread to fit.
  init() {
    super.init(frame: .zero)
    setContentHuggingPriority(.defaultLow, for: .vertical)
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel("Indicator position")
  }

  static func name(of position: IndicatorPosition) -> String {
    let rows = ["Top", "Upper middle", "Middle", "Lower middle", "Bottom"]
    let columns = ["left", "centre", "right"]
    return "\(rows[position.row]) \(columns[position.column])"
  }

  private lazy var places = IndicatorPosition.all.map { IndicatorPlaceElement(picker: self, position: $0) }
  override func accessibilityChildren() -> [Any]? { places }
  override func accessibilityValue() -> Any? { Self.name(of: indicator.position) }
  override var focusRadius: CGFloat { SettingsStyle.trackRadius }

  /// Left and right move along a row, up and down along a column.
  override func keyDown(with event: NSEvent) {
    var position = indicator.position
    switch Int(event.keyCode) {
    case kVK_LeftArrow: position.column = max(position.column - 1, 0)
    case kVK_RightArrow: position.column = min(position.column + 1, IndicatorPosition.columns - 1)
    case kVK_UpArrow: position.row = max(position.row - 1, 0)
    case kVK_DownArrow: position.row = min(position.row + 1, IndicatorPosition.rows - 1)
    default: return super.keyDown(with: event)
    }
    select(position)
  }

  fileprivate func select(_ position: IndicatorPosition) {
    guard isActive else { return }
    indicator.position = position
    needsDisplay = true
    onSelect?()
  }

  fileprivate func frame(of position: IndicatorPosition) -> NSRect {
    mark(at: position, size: Self.markSize).insetBy(dx: -6, dy: -6)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  private func mark(at position: IndicatorPosition, size: NSSize) -> NSRect {
    guard let screen = NSScreen.main else { return .zero }
    let origin = position.origin(for: size, in: screen.visibleFrame)
    let scale = bounds.width / screen.frame.width
    let center = NSPoint(x: (origin.x + size.width / 2 - screen.frame.minX) * scale,
                         y: (origin.y + size.height / 2 - screen.frame.minY) * bounds.height / screen.frame.height)
    return NSRect(x: center.x - size.width * scale / 2, y: center.y - size.height * scale / 2,
                  width: size.width * scale, height: size.height * scale)
  }

  private func nearest(to event: NSEvent) -> IndicatorPosition? {
    let point = convert(event.locationInWindow, from: nil)
    let size = Self.markSize
    return IndicatorPosition.all.min {
      let first = mark(at: $0, size: size), second = mark(at: $1, size: size)
      return hypot(first.midX - point.x, first.midY - point.y) < hypot(second.midX - point.x, second.midY - point.y)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    SettingsStyle.track.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: SettingsStyle.trackRadius, yRadius: SettingsStyle.trackRadius).fill()

    let size = Self.markSize
    let selected = indicator.position
    for position in IndicatorPosition.all where position != selected {
      let center = mark(at: position, size: size)
      SettingsStyle.secondary.withAlphaComponent(0.55).setFill()
      NSBezierPath(ovalIn: NSRect(x: center.midX - 3.5, y: center.midY - 3.5, width: 7, height: 7)).fill()
    }
    if let hovered, hovered != selected {
      SettingsStyle.switchOn.withAlphaComponent(0.4).setFill()
      drawMark(at: hovered, size: size)
    }
    SettingsStyle.switchOn.setFill()
    drawMark(at: selected, size: size)
  }

  /// Half again as large as true scale, so the mark stands out from the places.
  private func drawMark(at position: IndicatorPosition, size: NSSize) {
    var rect = mark(at: position, size: size)
    rect = rect.insetBy(dx: -rect.width / 4, dy: -rect.height / 4)
    rect.origin.x = min(max(rect.minX, 6), bounds.maxX - rect.width - 6)
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self))
  }
  override func mouseMoved(with event: NSEvent) { hovered = nearest(to: event) }
  override func mouseExited(with event: NSEvent) { hovered = nil }
  override func mouseDown(with event: NSEvent) {
    guard let position = nearest(to: event) else { return }
    select(position)
  }
}

/// One VoiceOver radio button per place.
private final class IndicatorPlaceElement: NSAccessibilityElement {
  private weak var picker: IndicatorPositionPicker?
  private let position: IndicatorPosition

  init(picker: IndicatorPositionPicker, position: IndicatorPosition) {
    self.picker = picker
    self.position = position
    super.init()
    setAccessibilityParent(picker)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(IndicatorPositionPicker.name(of: position))
  }

  override func accessibilityValue() -> Any? {
    MainActor.assumeIsolated { SpaceIndicator.shared.position == position }
  }
  override func accessibilityFrameInParentSpace() -> NSRect { picker?.frame(of: position) ?? .zero }
  override func accessibilityPerformPress() -> Bool {
    picker?.select(position)
    return picker != nil
  }
}
