import AppKit

@main
class MaccelerateApp {
  static func main() {
    let app = NSApplication.shared
    #if DEBUG
    if CommandLine.arguments.contains("--preview-settings")
      || Bundle.main.object(forInfoDictionaryKey: "MacceleratePreview") as? Bool == true {
      let preview = SettingsPreview()
      app.delegate = preview
      withExtendedLifetime(preview) { app.run() }
      return
    }
    #endif
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
