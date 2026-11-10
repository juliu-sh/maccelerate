#if DEBUG
import AppKit

/// Launch the settings without event taps or login registration.
@MainActor
final class SettingsPreview: NSObject, NSApplicationDelegate {
  private var controller: PreferencesWindowController?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let appearance = Bundle.main.object(forInfoDictionaryKey: "MacceleratePreviewAppearance") as? String
    if CommandLine.arguments.contains("--light") || appearance == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
    if CommandLine.arguments.contains("--dark") || appearance == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
    controller = PreferencesWindowController()
    controller?.present()
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--page"), arguments.indices.contains(index + 1),
       let page = Int(arguments[index + 1]) {
      (controller?.window?.contentViewController as? PreferencesTabViewController)?.select(page: page)
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
