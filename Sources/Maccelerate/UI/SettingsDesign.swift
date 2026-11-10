import AppKit

/// Layout helpers shared by the settings pages and the menu bar panel.
enum SettingsDesign {
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
  var fillColor: NSColor = SettingsStyle.canvas { didSet { needsDisplay = true } }
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
