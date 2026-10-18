import AppKit

/// AppKit owns the material, border, pointer and screen-edge placement.
@MainActor
final class CleanerPopover: NSPopover {
  static let contentWidth: CGFloat = 420
  static let contentHeight: CGFloat = 580
  static let quitContentHeight: CGFloat = 64
  static let animationDuration: TimeInterval = 0.18

  var didDismiss: (() -> Void)?
  var darkTheme = false {
    didSet {
      if darkTheme != oldValue { configureAppearance() }
    }
  }
  private(set) var isPresented = false
  private var generation = 0
  private var presentationAnchor: CleanerPresentationAnchor?
  private var accessibilityObserver: NSObjectProtocol?
  var window: NSWindow? { contentViewController?.view.window }

  func present(relativeTo rect: NSRect, of view: NSView) {
    guard let sourceWindow = view.window else { return }
    generation += 1
    isPresented = true
    animates = false
    if !isShown {
      let screenRect = sourceWindow.convertToScreen(view.convert(rect, to: nil))
      let anchor = CleanerPresentationAnchor(screenRect: screenRect)
      presentationAnchor = anchor
      anchor.orderFront(nil)
      configureAppearance()
      show(
        relativeTo: anchor.positioningView.bounds, of: anchor.positioningView,
        preferredEdge: .minY)
      window?.alphaValue = 0
    }
    window?.makeKey()
    window?.makeFirstResponder(nil)
    configureAppearance()
    if accessibilityObserver == nil {
      accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.configureAppearance() }
      }
    }
    animate { [weak self] in self?.window?.animator().alphaValue = 1 }
  }

  override func close() {
    if let accessibilityObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
      self.accessibilityObserver = nil
    }
    super.close()
    presentationAnchor?.orderOut(nil)
    presentationAnchor = nil
    isPresented = false
  }

  func dismissAnimated() {
    guard isPresented else { return }
    isPresented = false
    generation += 1
    let current = generation
    animate(
      { [weak self] in self?.window?.animator().alphaValue = 0 },
      completion: { [weak self] in
        guard let self, self.generation == current, !self.isPresented else { return }
        self.close()
        self.didDismiss?()
      })
  }

  func resize(to size: NSSize, animated: Bool) {
    guard contentSize != size else { return }
    let previousFrame = window?.frame
    contentSize = size
    configureAppearance()
    guard animated, isPresented, let window, let previousFrame else { return }
    let targetFrame = window.frame
    window.setFrame(previousFrame, display: false)
    animate { window.animator().setFrame(targetFrame, display: true) }
  }

  private func configureAppearance() {
    let standard: NSAppearance.Name = darkTheme ? .darkAqua : .aqua
    let highContrast: NSAppearance.Name =
      darkTheme ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
    appearance =
      NSAppearance(
        named: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
          ? highContrast : standard) ?? NSAppearance(named: standard)
    guard #available(macOS 26.0, *), let content = contentViewController?.view,
      let frame = window?.contentView?.superview
    else { return }
    let tinted =
      !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
      && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    // AppKit supplies the glass, border and pointer. Only style its backdrop;
    // the hosting view's controls retain their own native glass treatment.
    func configure(_ view: NSView) {
      guard view !== content else { return }
      if let glass = view as? NSGlassEffectView {
        glass.style = .regular
        glass.tintColor =
          tinted ? (darkTheme ? NSColor.black : .white).withAlphaComponent(0.12) : nil
        return
      }
      view.subviews.forEach(configure)
    }
    configure(frame)
  }

  private func animate(_ changes: () -> Void, completion: (@MainActor @Sendable () -> Void)? = nil)
  {
    NSAnimationContext.runAnimationGroup { context in
      context.duration =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ? 0 : Self.animationDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      changes()
    } completionHandler: {
      MainActor.assumeIsolated { completion?() }
    }
  }
}

/// A transparent, noninteractive host keeps native popover placement independent of menu bar layout.
@MainActor
private final class CleanerPresentationAnchor: NSWindow {
  let positioningView = NSView()

  init(screenRect: NSRect) {
    super.init(
      contentRect: screenRect, styleMask: [.borderless],
      backing: .buffered, defer: false)
    contentView = positioningView
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    level = .statusBar
    collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    setFrame(screenRect, display: false)
    setAccessibilityElement(false)
    positioningView.setAccessibilityElement(false)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Locates the eraser when opening the popover and positions its warning badge.
@MainActor
final class CleanerStatusAnchor: NSView {
  init(in view: NSView, trailingInset: CGFloat) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setAccessibilityElement(false)
    view.addSubview(self)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 18),
      trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -trailingInset),
      topAnchor.constraint(equalTo: view.topAnchor),
      bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
