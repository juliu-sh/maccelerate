import AppKit
import ISS

final class MenuSummaryView: NSView {
  private let location = SettingsDesign.text("Spaces unavailable", size: 20, weight: .semibold)
  private let detail = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 100))
    let brand = SettingsDesign.stack([
      SymbolTile(symbol: "arrow.left.and.right"),
      SettingsDesign.stack([
        SettingsDesign.text("Maccelerate", size: 13, weight: .semibold),
        SettingsDesign.text("A little faster. A lot more flow.", size: 10, color: .secondaryLabelColor),
      ], spacing: 2),
    ], vertical: false, spacing: 10)
    let current = SettingsDesign.stack([location, NSView(), detail], vertical: false, spacing: 8)
    let content = SettingsDesign.stack([brand, current], spacing: 14)
    SettingsDesign.pin(content, to: self, inset: 14)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(_ info: ISSSpaceInfo?) {
    guard let info, info.spaceCount > 0 else {
      location.stringValue = "Spaces unavailable"
      detail.stringValue = ""
      return
    }
    location.stringValue = "Space \(info.currentIndex + 1)"
    detail.stringValue = "of \(info.spaceCount) on this display"
  }
}
