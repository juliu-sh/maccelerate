import AppKit
import ISS

enum MenuBarIconRenderer {
  static func renderIcon(for info: ISSSpaceInfo) -> NSImage? {
    let iconSize: CGFloat = 18
    let cornerRadius: CGFloat = 6
    let borderWidth: CGFloat = 1.5
    let displayText = String(Int(info.currentIndex) + 1)

    let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
      .insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.lineWidth = borderWidth
    NSColor.black.setStroke()
    path.stroke()

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: iconSize * 0.6, weight: .bold),
      .foregroundColor: NSColor.black,
    ]

    let textSize = displayText.size(withAttributes: attributes)
    let textRect = NSRect(
      x: (iconSize - textSize.width) / 2,
      y: (iconSize - textSize.height) / 2,
      width: textSize.width,
      height: textSize.height
    )

    displayText.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()
    image.isTemplate = true
    return image
  }
}
