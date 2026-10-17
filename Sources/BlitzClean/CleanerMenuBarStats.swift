import Combine
import Foundation

@MainActor
final class CleanerMenuBarStats: ObservableObject {
  struct Display: Equatable {
    var showCPU = true
    var showMemory = true
    var showDisk = true
    var memoryDisplay = MenuBarMemoryDisplay.available

    var count: Int { [showCPU, showMemory, showDisk].filter { $0 }.count }

    func title(for snapshot: SystemSnapshot?) -> String {
      MenuBarStatusText.make(
        .init(
          snapshot: snapshot ?? .empty, showDisk: showDisk, showCPU: showCPU,
          showMemory: showMemory, memoryDisplay: memoryDisplay))
    }
  }

  @Published var enabled: Bool {
    didSet {
      defaults.set(enabled, forKey: Self.preferenceKey)
      updateSampling()
    }
  }
  @Published var display: Display {
    didSet {
      defaults.set(display.showCPU, forKey: MenuBarPreferenceKey.showCPU)
      defaults.set(display.showMemory, forKey: MenuBarPreferenceKey.showMemory)
      defaults.set(display.showDisk, forKey: MenuBarPreferenceKey.showDisk)
      defaults.set(display.memoryDisplay.rawValue, forKey: MenuBarPreferenceKey.memoryDisplay)
    }
  }
  @Published private(set) var snapshot: SystemSnapshot?

  private static let preferenceKey = "cleaner.showMenuBarStats"
  private let defaults: UserDefaults
  private let readSample: () -> SystemSnapshot
  private var timer: Timer?
  private var started = false

  init(defaults: UserDefaults = .standard, readSample: (() -> SystemSnapshot)? = nil) {
    self.defaults = defaults
    enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
    var display = Display(
      showCPU: defaults.object(forKey: MenuBarPreferenceKey.showCPU) as? Bool ?? true,
      showMemory: defaults.object(forKey: MenuBarPreferenceKey.showMemory) as? Bool ?? true,
      showDisk: defaults.object(forKey: MenuBarPreferenceKey.showDisk) as? Bool ?? true,
      memoryDisplay: MenuBarMemoryDisplay(
        rawValue: defaults.string(forKey: MenuBarPreferenceKey.memoryDisplay) ?? "") ?? .available)
    if display.count == 0 { display.showCPU = true }
    self.display = display
    let provider = SystemMetricsProvider()
    self.readSample = readSample ?? { provider.snapshot() }
  }

  func start() {
    guard !started else { return }
    started = true
    updateSampling()
  }

  func stop() {
    started = false
    updateSampling()
  }

  private func updateSampling() {
    timer?.invalidate()
    timer = nil
    guard started && enabled else {
      snapshot = nil
      return
    }
    snapshot = readSample()
    let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.started, self.enabled else { return }
        self.snapshot = self.readSample()
      }
    }
    timer.tolerance = 0.25
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
}
