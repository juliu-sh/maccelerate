import AppKit
import Combine
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
  static let shared = UpdaterManager()

  @Published private(set) var canCheckForUpdates = false
  private var controller: SPUStandardUpdaterController!
  private var previousActivationPolicy: NSApplication.ActivationPolicy?
  private var started = false

  private override init() {
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    controller.updater.publisher(for: \.canCheckForUpdates)
      .map { [weak self] available in available && (self?.started ?? false) }
      .assign(to: &$canCheckForUpdates)
  }

  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  func start() {
    #if !DEBUG
    // Raw SwiftPM executables and UI previews must never update the installed app.
    guard Bundle.main.bundleURL.pathExtension == "app",
      Bundle.main.object(forInfoDictionaryKey: "MaccelerateBuildChannel") as? String == "official",
      Bundle.main.object(forInfoDictionaryKey: "MaccelerateEdition") as? String == "free",
      Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String,
      Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String else { return }
    started = true
    controller.startUpdater()
    canCheckForUpdates = controller.updater.canCheckForUpdates
    #endif
  }

  @objc func checkForUpdates(_ sender: Any?) {
    guard canCheckForUpdates else { return }
    showUpdateUI()
    controller.checkForUpdates(sender)
  }

  private func showUpdateUI() {
    if previousActivationPolicy == nil { previousActivationPolicy = NSApp.activationPolicy() }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func standardUserDriverWillShowModalAlert() { showUpdateUI() }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    if handleShowingUpdate { showUpdateUI() }
  }

  func standardUserDriverWillFinishUpdateSession() {
    guard let policy = previousActivationPolicy else { return }
    previousActivationPolicy = nil
    DispatchQueue.main.async {
      // Keep the Dock icon if Settings or another app window was opened meanwhile.
      if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) {
        NSApp.setActivationPolicy(policy)
      }
    }
  }
}
