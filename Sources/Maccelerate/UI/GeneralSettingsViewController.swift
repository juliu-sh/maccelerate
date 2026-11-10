import AppKit
import Combine
import ISS
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
  private let speedControl = SettingsSegmented(titles: SwitchingMode.titles, selected: 0,
                                               label: "Switching speed")
  private let swipeSwitch = SettingsSwitch(label: "Trackpad swipes")
  private let cmdTabSwitch = SettingsSwitch(label: "App switching")
  private let detectionSwitch = SettingsSwitch(label: "Mission Control and Exposé detection")
  private lazy var accelerationGate = SettingsGate(accelerationRows())
  private let stageSpeedControl = SettingsSegmented(titles: StageManagerSpeed.allCases.map(\.title),
                                                    selected: 0, label: "Stage Manager animation speed")
  private let stageStripSwitch = SettingsSwitch(label: "Show recent apps instantly")
  private let stageDockSwitch = SettingsSwitch(label: "Shift-click in the Dock adds to stage")
  private let stageStatus = SettingsDesign.text("", size: 11, color: SettingsStyle.secondary)
  private let loginSwitch = SettingsSwitch(label: "Launch at login")
  private let loginStatus = SettingsDesign.text("", size: 11, color: SettingsStyle.secondary)
  private let updateSwitch = SettingsSwitch(label: "Automatically check for updates")
  private let updateButton = SettingsButton("Check for Updates…") {
    UpdaterManager.shared.checkForUpdates(nil)
  }
  private var subscriptions = Set<AnyCancellable>()
  private let defaults = UserDefaults.standard

  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    let speed = SettingsCard(title: "Switching speed")
    speed.add(speedControl, spacingAfter: 10)
    speed.add(accelerationGate)
    // System is the off state: macOS runs its own animation, so these have nothing to do.
    speedControl.onChange = { segment in
      if let mode = SwitchingMode(segment: segment) { SwitchingMode.select(mode) }
    }
    swipeSwitch.onChange = { [weak self] isOn in
      self?.defaults.set(isOn, forKey: "swipeOverride")
      SwitchingMode.apply()
    }
    cmdTabSwitch.onChange = { [weak self] in self?.defaults.set($0, forKey: "accelerateCmdTab") }
    detectionSwitch.onChange = { [weak self] isOn in
      self?.defaults.set(isOn, forKey: "overlayDetectionEnabled")
      iss_set_overlay_detection_enabled(isOn)
    }

    let stage = SettingsCard(title: "Stage Manager")
    stage.add(stage.divider())
    stage.add(SettingsStyle.row("Animation speed", note: "A hidden macOS setting. It stays until you choose System.",
                                control: NSView()))
    stage.add(stageSpeedControl, spacingAfter: 6)
    stageStatus.isHidden = true
    stage.add(stageStatus, spacingAfter: 6)
    stage.addRows([
      SettingsStyle.row("Show recent apps instantly", control: stageStripSwitch),
      SettingsStyle.row("Shift-click in the Dock adds to stage", note: "Experimental", control: stageDockSwitch),
    ])
    stageSpeedControl.onChange = { index in
      // WindowManager picks up AnimationSpeed immediately; no restart needed.
      if let speed = StageManagerSpeed(rawValue: index) { StageManagerTuning.setSpeed(speed) }
    }
    stageStripSwitch.onChange = { [weak self] isOn in
      StageManagerTuning.setShowsRecentAppsInstantly(isOn)
      self?.offerStageManagerRestart()
    }
    stageDockSwitch.onChange = { [weak self] in self?.defaults.set($0, forKey: StageDockClick.enabledKey) }

    let everyday = SettingsCard(title: "Everyday use")
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    loginStatus.isHidden = true
    everyday.addRows([SettingsStyle.row("Launch at login", control: loginSwitch)])
    everyday.add(loginStatus, spacingAfter: 8)
    everyday.addRows([
      SettingsStyle.row("Automatically check for updates", control: updateSwitch),
      SettingsStyle.row("Version \(version)", control: updateButton),
    ])
    loginSwitch.onChange = { [weak self] in self?.loginChanged($0) }
    updateSwitch.onChange = { UpdaterManager.shared.automaticallyChecksForUpdates = $0 }
    UpdaterManager.shared.$canCheckForUpdates.sink { [weak self] available in
      self?.updateButton.isEnabled = available
    }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: SwitchingMode.didChange)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.loadSettings() }
      .store(in: &subscriptions)

    SettingsDesign.page(SettingsDesign.stack([speed, stage, everyday], spacing: SettingsStyle.cardGap), in: view)
    loadSettings()
  }

  override func viewWillAppear() { super.viewWillAppear(); loadSettings() }

  private func accelerationRows() -> NSView {
    let rows = SettingsDesign.stack(spacing: 0)
    for row in [
      SettingsStyle.row("Trackpad swipes", control: swipeSwitch),
      SettingsStyle.row("App switching", note: "When ⌘ Tab leads to another Space.", control: cmdTabSwitch),
      SettingsStyle.row("Mission Control & Exposé", note: "Experimental. Detects open overviews.",
                        control: detectionSwitch),
    ] {
      let line = SettingsFill(SettingsStyle.divider)
      line.heightAnchor.constraint(equalToConstant: 1).isActive = true
      for view in [line, row] {
        rows.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      }
    }
    return rows
  }

  private func loadSettings() {
    let mode = SwitchingMode.current()
    speedControl.selected = mode.segment
    accelerationGate.isOpen = mode.accelerates
    swipeSwitch.isOn = defaults.bool(forKey: "swipeOverride")
    cmdTabSwitch.isOn = defaults.object(forKey: "accelerateCmdTab") as? Bool ?? true
    detectionSwitch.isOn = defaults.object(forKey: "overlayDetectionEnabled") as? Bool ?? true
    stageSpeedControl.selected = StageManagerTuning.speed?.rawValue ?? -1
    stageStripSwitch.isOn = StageManagerTuning.showsRecentAppsInstantly
    stageDockSwitch.isOn = StageDockClick.isEnabled
    setStageStatus(StageManagerTuning.speed == nil
                   ? "Stage Manager uses a custom animation speed set outside Maccelerate." : nil)
    updateSwitch.isOn = UpdaterManager.shared.automaticallyChecksForUpdates
    #if DEBUG
    updateSwitch.isEnabled = false
    #endif
    let status = SMAppService.mainApp.status
    loginSwitch.isOn = status == .enabled || status == .requiresApproval
    setLoginStatus(status == .requiresApproval
                   ? "Allow Maccelerate in System Settings → General → Login Items to finish setup." : nil)
  }

  private func setStageStatus(_ message: String?, error: Bool = false) {
    stageStatus.stringValue = message ?? ""
    stageStatus.textColor = error ? .systemRed : SettingsStyle.secondary
    stageStatus.isHidden = message == nil
  }

  private func setLoginStatus(_ message: String?, error: Bool = false) {
    loginStatus.stringValue = message ?? ""
    loginStatus.textColor = error ? .systemRed : SettingsStyle.secondary
    loginStatus.isHidden = message == nil
  }

  private func offerStageManagerRestart() {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Restart Stage Manager now?"
    alert.informativeText = "Stage Manager applies the change after it restarts or after you log in again. "
      + "A restart takes a moment; your windows stay open."
    alert.addButton(withTitle: "Restart Now")
    alert.addButton(withTitle: "Later")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      let restarted = StageManagerTuning.restartStageManager()
      self?.setStageStatus(restarted ? nil : "Couldn’t restart Stage Manager. Log out and in to apply.",
                           error: true)
    }
  }

  private func loginChanged(_ isOn: Bool) {
    do {
      if isOn { try SMAppService.mainApp.register() }
      else { try SMAppService.mainApp.unregister() }
      loadSettings()
    } catch {
      loginSwitch.isOn = SMAppService.mainApp.status == .enabled
      setLoginStatus("Couldn’t update launch at login. \(error.localizedDescription)", error: true)
    }
  }
}
