import AppKit
import Combine
import ISS
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
  private let swipeSwitch = NSSwitch()
  private let cmdTabSwitch = NSSwitch()
  private let detectionSwitch = NSSwitch()
  private let loginSwitch = NSSwitch()
  private let updateSwitch = NSSwitch()
  private let updateButton = NSButton(title: "Check for Updates…", target: nil, action: nil)
  private var updateSubscription: AnyCancellable?
  private let speedControl = NSSegmentedControl(labels: SwitchingSpeedPreset.allCases.map(\.title),
                                               trackingMode: .selectOne, target: nil, action: nil)
  private let speedLabel = SettingsDesign.text("", size: 28, weight: .semibold)
  private let illustration = SpaceIllustration()
  private let loginStatus = SettingsDesign.text("", size: 11, color: .secondaryLabelColor)
  private let defaults = UserDefaults.standard

  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    let intro = SettingsDesign.heading("Move at your own speed.", subtitle: "Fine-tune how you move between macOS Spaces.")
    let speedText = SettingsDesign.stack([
      SettingsDesign.text("Switching speed", size: 12, weight: .medium, color: .secondaryLabelColor),
      speedLabel,
      SettingsDesign.text("Less waiting. More flow.", size: 12, color: .secondaryLabelColor),
    ], spacing: 5)
    illustration.widthAnchor.constraint(equalToConstant: 238).isActive = true
    let hero = SettingsDesign.stack([speedText, NSView(), illustration], vertical: false, spacing: 16)
    hero.heightAnchor.constraint(equalToConstant: 74).isActive = true
    speedControl.segmentStyle = .rounded
    speedControl.controlSize = .large
    speedControl.target = self
    speedControl.action = #selector(speedChanged)
    speedControl.setAccessibilityLabel("Switching speed")
    speedControl.segmentDistribution = .fillEqually
    let speedContents = SettingsDesign.stack([hero, speedControl], spacing: 12)
    hero.widthAnchor.constraint(equalTo: speedContents.widthAnchor).isActive = true
    speedControl.widthAnchor.constraint(equalTo: speedContents.widthAnchor).isActive = true
    speedControl.heightAnchor.constraint(equalToConstant: 32).isActive = true
    let speedCard = SettingsDesign.card([speedContents], padding: 18)

    configure(swipeSwitch, title: "Accelerate trackpad swipes", action: #selector(swipeChanged))
    configure(cmdTabSwitch, title: "Accelerate app switching", action: #selector(cmdTabChanged))
    configure(detectionSwitch, title: "Detect Mission Control and Exposé", action: #selector(detectionChanged))
    configure(loginSwitch, title: "Launch at login", action: #selector(loginChanged))
    configure(updateSwitch, title: "Automatically check for updates", action: #selector(updatesChanged))
    updateButton.target = UpdaterManager.shared
    updateButton.action = #selector(UpdaterManager.checkForUpdates(_:))
    updateButton.bezelStyle = .rounded
    updateSubscription = UpdaterManager.shared.$canCheckForUpdates.sink { [weak self] available in
      self?.updateButton.isEnabled = available
    }
    let behavior = SettingsDesign.card([
      SettingsDesign.row("Trackpad swipes", detail: "Apply your speed to the system swipe gesture.",
                         symbol: "hand.draw", control: swipeSwitch),
      SettingsDesign.row("App switching", detail: "Speed up ⌘ Tab when an app is on another Space.",
                         symbol: "square.on.square", control: cmdTabSwitch),
      SettingsDesign.row("Mission Control & Exposé", detail: "Detect open overviews. Experimental; may be unreliable.",
                         symbol: "rectangle.3.group", control: detectionSwitch),
    ], padding: 12)
    let system = SettingsDesign.card([
      SettingsDesign.row("Launch at login", detail: "Keep Maccelerate ready in your menu bar.",
                         symbol: "power", control: loginSwitch),
    ], padding: 12)
    let content = SettingsDesign.stack([
      intro, speedCard, SettingsDesign.section("Switching behavior", content: behavior),
      SettingsDesign.section("Everyday use", content: system), loginStatus,
      SettingsDesign.section("Updates", content: SettingsDesign.card([
        SettingsDesign.row("Automatically check", detail: "Keep Maccelerate up to date.",
          symbol: "arrow.triangle.2.circlepath", control: updateSwitch),
        updateButton,
      ], padding: 12)),
    ], spacing: 18)
    SettingsDesign.page(content, in: view)
    loadSettings()
  }

  override func viewWillAppear() { super.viewWillAppear(); loadSettings() }

  private func configure(_ control: NSSwitch, title: String, action: Selector) {
    control.target = self
    control.action = action
    control.setAccessibilityLabel(title)
  }

  private func loadSettings() {
    updateSwitch.state = UpdaterManager.shared.automaticallyChecksForUpdates ? .on : .off
    #if DEBUG
    updateSwitch.isEnabled = false
    #endif
    swipeSwitch.state = defaults.bool(forKey: "swipeOverride") ? .on : .off
    cmdTabSwitch.state = (defaults.object(forKey: "accelerateCmdTab") as? Bool ?? true) ? .on : .off
    detectionSwitch.state = (defaults.object(forKey: "overlayDetectionEnabled") as? Bool ?? true) ? .on : .off
    let speed = SwitchingSpeedPreset.fromStoredVelocity(defaults.double(forKey: "gestureSpeed"))
    speedControl.selectedSegment = speed.rawValue
    speedLabel.stringValue = speed.title
    illustration.boostCount = speed.boostCount
    let status = SMAppService.mainApp.status
    loginSwitch.state = status == .enabled || status == .requiresApproval ? .on : .off
    loginStatus.stringValue = status == .requiresApproval
      ? "Allow Maccelerate in System Settings → General → Login Items to finish setup." : ""
    loginStatus.isHidden = loginStatus.stringValue.isEmpty
  }

  @objc private func updatesChanged(_ sender: NSSwitch) {
    UpdaterManager.shared.automaticallyChecksForUpdates = sender.state == .on
  }

  @objc private func swipeChanged(_ sender: NSSwitch) {
    defaults.set(sender.state == .on, forKey: "swipeOverride")
    iss_set_swipe_override(sender.state == .on)
  }

  @objc private func cmdTabChanged(_ sender: NSSwitch) {
    defaults.set(sender.state == .on, forKey: "accelerateCmdTab")
  }

  @objc private func detectionChanged(_ sender: NSSwitch) {
    defaults.set(sender.state == .on, forKey: "overlayDetectionEnabled")
    iss_set_overlay_detection_enabled(sender.state == .on)
  }

  @objc private func speedChanged(_ sender: NSSegmentedControl) {
    guard let speed = SwitchingSpeedPreset(rawValue: sender.selectedSegment) else { return }
    defaults.set(speed.velocity, forKey: "gestureSpeed")
    iss_set_gesture_speed(speed.velocity)
    speedLabel.stringValue = speed.title
    illustration.boostCount = speed.boostCount
  }

  @objc private func loginChanged(_ sender: NSSwitch) {
    do {
      if sender.state == .on { try SMAppService.mainApp.register() }
      else { try SMAppService.mainApp.unregister() }
      loadSettings()
    } catch {
      sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
      loginStatus.stringValue = "Couldn’t update launch at login. \(error.localizedDescription)"
      loginStatus.textColor = .systemRed
      loginStatus.isHidden = false
    }
  }
}
