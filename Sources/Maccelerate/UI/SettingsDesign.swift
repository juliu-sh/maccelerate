import AppKit

/// Shared native surfaces and spacing for settings and menu summaries.
enum SettingsDesign {
  static let accent = NSColor.controlAccentColor
  static let canvas = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.99, alpha: 1)
  }
  static let surface = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(white: 0.23, alpha: 1) : NSColor(white: 0.95, alpha: 1)
  }
  static let inset = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.90, alpha: 1)
  }

  static func text(_ title: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: title)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }

  static func stack(_ views: [NSView] = [], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = vertical ? .vertical : .horizontal
    stack.alignment = vertical ? .leading : .centerY
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  static func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
  }

  static func heading(_ title: String, subtitle: String) -> NSView {
    stack([text(title, size: 25, weight: .semibold),
           text(subtitle, size: 13, color: .secondaryLabelColor)], spacing: 5)
  }

  static func section(_ title: String, content: NSView) -> NSView {
    let heading = text(title, size: 12, weight: .semibold, color: .secondaryLabelColor)
    let group = stack([heading, content], spacing: 9)
    content.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
    return group
  }

  static func card(_ rows: [NSView], padding: CGFloat = 18) -> NSView {
    let surface = SettingsSurface()
    let content = stack(spacing: 0)
    for (index, row) in rows.enumerated() {
      if index > 0 {
        let divider = NSBox()
        divider.boxType = .separator
        content.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
      }
      content.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    pin(content, to: surface, inset: padding)
    return surface
  }

  static func row(_ title: String, detail: String? = nil, symbol: String? = nil,
                  control: NSView, height: CGFloat = 56) -> NSView {
    let texts = stack([text(title, weight: .medium)], spacing: 3)
    if let detail { texts.addArrangedSubview(text(detail, size: 11, color: .secondaryLabelColor)) }
    var items: [NSView] = []
    if let symbol { items.append(SymbolTile(symbol: symbol)) }
    items += [texts, NSView(), control]
    let row = stack(items, vertical: false, spacing: 12)
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    control.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
    return row
  }

  static func button(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .large
    return button
  }

  static func page(_ content: NSStackView, in parent: NSView) {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    let document = FlippedSettingsView()
    document.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = document
    pin(scroll, to: parent)
    content.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(content)
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      content.topAnchor.constraint(equalTo: document.topAnchor, constant: 26),
      content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
      content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
      content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
    ])
    for child in content.arrangedSubviews {
      child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
  }
}

final class FlippedSettingsView: NSView {
  override var isFlipped: Bool { true }
}

class SettingsSurface: NSView {
  var fillColor: NSColor = SettingsDesign.surface { didSet { needsDisplay = true } }
  var radius: CGFloat = 18
  override func draw(_ dirtyRect: NSRect) {
    fillColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

final class SymbolTile: NSView {
  private let symbol: String
  init(symbol: String) {
    self.symbol = symbol
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 32), heightAnchor.constraint(equalToConstant: 32),
    ])
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func draw(_ dirtyRect: NSRect) {
    SettingsDesign.accent.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))?
      .withSymbolConfiguration(.init(paletteColors: [SettingsDesign.accent]))
    image?.draw(in: bounds.insetBy(dx: 8, dy: 8))
  }
}

/// Adjacent Spaces with a visible boost count for the selected speed preset.
final class SpaceIllustration: NSView {
  var boostCount = 1 {
    didSet {
      needsDisplay = true
      setAccessibilityLabel("Space 1, Space 2 with \(boostCount) speed boosts, Space 3")
    }
  }

  override var intrinsicContentSize: NSSize { NSSize(width: 238, height: 74) }

  override func draw(_ dirtyRect: NSRect) {
    let sideWidth: CGFloat = 48
    let centerWidth: CGFloat = 108
    let gap: CGFloat = 12
    let origin = (bounds.width - sideWidth * 2 - centerWidth - gap * 2) / 2
    let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))?
      .withSymbolConfiguration(.init(paletteColors: [SettingsDesign.accent]))

    for index in 0..<3 {
      let selected = index == 1
      let x = origin + (index == 0 ? 0 : index == 1 ? sideWidth + gap : sideWidth + gap + centerWidth + gap)
      let height: CGFloat = selected ? 54 : 44
      let rect = NSRect(x: x, y: bounds.midY - height / 2,
                        width: selected ? centerWidth : sideWidth, height: height)
      (selected ? SettingsDesign.accent.withAlphaComponent(0.16) : SettingsDesign.inset).setFill()
      let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
      path.fill()
      if selected {
        SettingsDesign.accent.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1.5
        path.stroke()
      }
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: selected ? 20 : 15, weight: .medium),
        .foregroundColor: selected ? SettingsDesign.accent : NSColor.secondaryLabelColor,
      ]
      let title = "\(index + 1)" as NSString
      let size = title.size(withAttributes: attributes)
      let titleX = selected ? rect.minX + 18 : rect.midX - size.width / 2
      title.draw(at: NSPoint(x: titleX, y: rect.midY - size.height / 2),
                 withAttributes: attributes)
      if selected {
        let symbolWidth: CGFloat = 12
        let spacing: CGFloat = 4
        let count = min(max(boostCount, 1), 3)
        let totalWidth = CGFloat(count) * symbolWidth + CGFloat(count - 1) * spacing
        let startX = rect.maxX - 15 - totalWidth
        for boost in 0..<count {
          bolt?.draw(in: NSRect(x: startX + CGFloat(boost) * (symbolWidth + spacing),
                                y: rect.midY - 8, width: symbolWidth, height: 16))
        }
      }
    }
  }
}
