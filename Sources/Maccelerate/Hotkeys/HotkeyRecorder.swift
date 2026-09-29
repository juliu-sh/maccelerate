import AppKit
import Carbon

@MainActor
final class HotkeyRecorder {
  static let shared = HotkeyRecorder()

  private var monitor: Any?
  private var completion: ((HotkeyCombination) -> Void)?
  private var cancellation: (() -> Void)?

  private init() {}

  func beginRecording(
    for identifier: HotkeyIdentifier,
    completion: @escaping (HotkeyCombination) -> Void,
    cancellation: @escaping () -> Void
  ) {
    endRecording()

    self.completion = completion
    self.cancellation = cancellation

    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: handle(event:))
    NSApp.activate(ignoringOtherApps: true)
  }

  func endRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    completion = nil
    cancellation = nil
  }

  private func handle(event: NSEvent) -> NSEvent? {
    guard let completion else {
      return event
    }

    if event.keyCode == UInt16(kVK_Escape) {
      cancellation?()
      endRecording()
      return nil
    }

    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      NSSound.beep()
      return nil
    }

    completion(combination)
    endRecording()
    return nil
  }
}
