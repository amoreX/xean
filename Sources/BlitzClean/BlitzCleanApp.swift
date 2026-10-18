import AppKit
import Combine
import SwiftUI

@MainActor
enum BlitzCleanApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var cleanerAnchor: CleanerStatusAnchor?
  private var cleanerPanel: CleanerPopover?
  private var cleanerHost: NSHostingController<CleanerView>?
  private var confirmingQuit = false
  private let launchAtLogin = LaunchAtLoginController()
  private let menuBarStats = CleanerMenuBarStats()
  private var statsSubscription: AnyCancellable?
  private var themeSubscription: AnyCancellable?
  private var menuBarAnimator: CleanerMenuBarAnimator?
  private let warningBadge = CleanerWarningBadge()
  private var localClickMonitor: Any?
  private var globalClickMonitor: Any?
  private var cleaner: CleanerModel?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    closeCleaner()
    cleaner?.stop()
    menuBarStats.stop()
    menuBarAnimator?.stop()
    return .terminateNow
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showCleaner()
    return true
  }

  func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }
  func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let menu = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "BlitzClean")
    let open = NSMenuItem(
      title: "Open cleaner…", action: #selector(showCleaner), keyEquivalent: ",")
    open.target = self
    applicationMenu.addItem(open)
    applicationMenu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit BlitzClean", action: #selector(requestQuit), keyEquivalent: "q")
    quit.target = self
    applicationMenu.addItem(quit)
    applicationItem.submenu = applicationMenu
    menu.addItem(applicationItem)
    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    let close = NSMenuItem(
      title: "Close", action: #selector(closeCleaner), keyEquivalent: "w")
    close.target = self
    windowMenu.addItem(close)
    windowItem.submenu = windowMenu
    menu.addItem(windowItem)
    NSApp.mainMenu = menu
    NSApp.windowsMenu = windowMenu
    let model = CleanerModel()
    cleaner = model
    themeSubscription = model.$darkTheme.removeDuplicates().sink { [weak self] dark in
      self?.cleanerPanel?.darkTheme = dark
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "eraser.fill", accessibilityDescription: "Open BlitzClean cleaner")
    item.button?.image?.isTemplate = true
    item.button?.toolTip = "BlitzClean · Clean up"
    item.button?.target = self
    item.button?.action = #selector(toggleCleaner)
    statusItem = item
    let icon = MenuBarLabelRenderer.image(
      content: MenuBarMetrics(
        snapshot: .empty, risk: .normal, showHealth: false,
        showCPU: false, showMemory: false, showDisk: false,
        memoryDisplay: .available, symbolName: "eraser.fill", symbolAtEnd: true), colored: false)
    let padding = max(4, NSStatusBar.system.thickness - icon.size.width)
    if let button = item.button {
      let anchor = CleanerStatusAnchor(in: button, trailingInset: padding / 2 + 1)
      cleanerAnchor = anchor
      warningBadge.translatesAutoresizingMaskIntoConstraints = false
      anchor.addSubview(warningBadge)
      NSLayoutConstraint.activate([
        warningBadge.widthAnchor.constraint(equalToConstant: 11),
        warningBadge.heightAnchor.constraint(equalToConstant: 11),
        warningBadge.leadingAnchor.constraint(equalTo: anchor.trailingAnchor, constant: -6),
        warningBadge.centerYAnchor.constraint(equalTo: anchor.centerYAnchor, constant: -3.5),
      ])
    }
    menuBarAnimator = CleanerMenuBarAnimator(icon: icon) { [weak item] image in
      guard let item else { return }
      item.button?.image = image
      item.length = image.size.width + padding
    }
    statsSubscription = menuBarStats.$enabled.combineLatest(
      menuBarStats.$snapshot, menuBarStats.$display,
      model.$available.combineLatest(model.$preferences).map { available, preferences in
        preferences.warningsEnabled && preferences.isBelowThreshold(available)
      }.removeDuplicates()
    )
    .sink { [weak self] enabled, snapshot, display, warning in
      self?.updateMenuBarStats(
        enabled: enabled, snapshot: snapshot, display: display, warning: warning)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(closeCleaner),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(closeCleaner), name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(showCleaner), name: .openWorkspace, object: nil)
    model.start()
    menuBarStats.start()
    // A normal launch stays in the menu bar; an explicit request opens the dialog.
    if CommandLine.arguments.contains("--cleaner") || CommandLine.arguments.contains("--workspace")
    {
      showCleaner()
    }
  }

  func applicationDidResignActive(_ notification: Notification) {
    closeCleaner()
  }

  private func updateMenuBarStats(
    enabled: Bool, snapshot: SystemSnapshot?, display: CleanerMenuBarStats.Display, warning: Bool
  ) {
    guard let button = statusItem?.button else { return }
    button.imagePosition = .imageOnly
    button.title = ""
    let image: NSImage?
    if enabled {
      image = MenuBarLabelRenderer.image(
        content: MenuBarMetrics(
          snapshot: snapshot ?? .empty, risk: .normal, showHealth: false,
          showCPU: display.showCPU, showMemory: display.showMemory, showDisk: display.showDisk,
          memoryDisplay: display.memoryDisplay, symbolName: "eraser.fill", symbolAtEnd: true),
        colored: false)
    } else {
      image = nil
    }
    menuBarAnimator?.update(
      image: image, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    button.toolTip =
      enabled
      ? "BlitzClean · " + display.title(for: snapshot) : "BlitzClean · Clean up"
    if warning { button.toolTip = "Low disk space · " + (button.toolTip ?? "BlitzClean") }
    button.setAccessibilityLabel(button.toolTip)
    warningBadge.isHidden = !warning
  }

  @objc private func toggleCleaner() {
    if cleanerPanel?.isPresented == true {
      closeCleaner()
    } else {
      showCleaner()
    }
  }

  @objc private func closeCleaner() {
    cleanerPanel?.dismissAnimated()
    statusItem?.button?.highlight(false)
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    localClickMonitor = nil
    globalClickMonitor = nil
  }

  @objc private func requestQuit() {
    if cleanerPanel?.isPresented != true { showCleaner() }
    setQuitConfirmation(true)
  }

  private func setQuitConfirmation(_ confirming: Bool) {
    guard confirmingQuit != confirming else { return }
    confirmingQuit = confirming
    positionCleaner(animated: true)
  }

  private func cancelCleaner() {
    if confirmingQuit {
      setQuitConfirmation(false)
    } else {
      closeCleaner()
    }
  }

  private func positionCleaner(animated: Bool) {
    guard let cleaner, let button = statusItem?.button, let panel = cleanerPanel else { return }
    cleanerHost?.rootView = CleanerView(
      model: cleaner, launchAtLogin: launchAtLogin, menuBarStats: menuBarStats,
      confirmingQuit: confirmingQuit,
      onQuitRequest: { [weak self] in self?.requestQuit() },
      onQuitCancel: { [weak self] in self?.setQuitConfirmation(false) },
      onClose: { [weak self] in self?.closeCleaner() })
    let availableHeight = (button.window?.screen?.visibleFrame.height ?? 700) - 32
    panel.resize(
      to: NSSize(
        width: CleanerPopover.contentWidth,
        height: confirmingQuit
          ? CleanerPopover.quitContentHeight
          : min(CleanerPopover.contentHeight, availableHeight)),
      animated: animated)
  }

  @objc func showCleaner() {
    guard let cleaner, let button = statusItem?.button, let cleanerAnchor else { return }
    if cleanerPanel == nil {
      let panel = CleanerPopover()
      panel.darkTheme = cleaner.darkTheme
      let controller = NSHostingController(
        rootView: CleanerView(
          model: cleaner, launchAtLogin: launchAtLogin, menuBarStats: menuBarStats))
      controller.sizingOptions = []
      panel.contentViewController = controller
      panel.behavior = .applicationDefined
      panel.animates = false
      panel.didDismiss = { [weak cleaner] in cleaner?.panelClosed() }
      cleanerHost = controller
      cleanerPanel = panel
    }
    guard let panel = cleanerPanel, !panel.isPresented else { return }
    cleaner.panelClosed()
    confirmingQuit = false
    positionCleaner(animated: false)
    button.layoutSubtreeIfNeeded()
    NSApp.activate(ignoringOtherApps: true)
    panel.present(relativeTo: cleanerAnchor.bounds, of: cleanerAnchor)
    button.highlight(true)
    localClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .keyDown]
    ) { [weak self] event in
      let dismissKey = MainActor.assumeIsolated {
        guard let self else { return false }
        if event.type == .keyDown {
          if event.keyCode == 53 && NSApp.modalWindow == nil {
            self.cancelCleaner()
            return true
          }
          return false
        }
        if event.window !== self.cleanerPanel?.window,
          event.window !== self.statusItem?.button?.window, NSApp.modalWindow == nil
        {
          self.closeCleaner()
        }
        return false
      }
      return dismissKey ? nil : event
    }
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown,
    ]) {
      [weak self] _ in
      Task { @MainActor in self?.closeCleaner() }
    }
    Task {
      await cleaner.refreshDisk()
    }
  }

}

@MainActor
final class CleanerWarningBadge: NSImageView {
  init() {
    super.init(frame: .zero)
    image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
    contentTintColor = .systemRed
    imageScaling = .scaleProportionallyUpOrDown
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) { return nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct InitialWindowRequest {
  private var pending: String?

  init(_ arguments: [String]) {
    if arguments.contains("--workspace") {
      pending = "workspace"
    } else if arguments.contains("--storage") {
      pending = "storage-breakdown"
    } else if arguments.contains("--memory-rescue") {
      pending = "memory-rescue"
    } else if arguments.contains("--app-recovery") {
      pending = "app-recovery"
    } else if !arguments.contains("--background") {
      pending = "dashboard"
    }
  }

  mutating func consume() -> String? {
    defer { pending = nil }
    return pending
  }
}

@MainActor
enum AppLaunch {
  static var initialWindow = InitialWindowRequest(CommandLine.arguments)
}
