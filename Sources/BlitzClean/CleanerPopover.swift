import AppKit

/// AppKit owns the material, border, pointer and screen-edge placement.
@MainActor
final class CleanerPopover: NSPopover {
  static let contentWidth: CGFloat = 420
  static let contentHeight: CGFloat = 580
  static let quitContentHeight: CGFloat = 64
  static let animationDuration: TimeInterval = 0.18

  var didDismiss: (() -> Void)?
  private(set) var isPresented = false
  private var generation = 0
  private var presentationAnchor: CleanerPresentationAnchor?
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
      appearance = NSAppearance(
        named: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
          ? .accessibilityHighContrastAqua : .aqua)
      show(
        relativeTo: anchor.positioningView.bounds, of: anchor.positioningView,
        preferredEdge: .minY)
      window?.alphaValue = 0
    }
    window?.makeKey()
    window?.makeFirstResponder(nil)
    animate { [weak self] in self?.window?.animator().alphaValue = 1 }
  }

  override func close() {
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
    guard animated, isPresented, let window, let previousFrame else { return }
    let targetFrame = window.frame
    window.setFrame(previousFrame, display: false)
    animate { window.animator().setFrame(targetFrame, display: true) }
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
