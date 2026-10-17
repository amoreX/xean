import AppKit
import SwiftUI

struct CleanerPopoverPlacement {
  static let quitContentHeight: CGFloat = 60
  let frame: NSRect
  let pointerX: CGFloat

  init(anchor: NSRect, visibleFrame: NSRect, contentHeight: CGFloat = 580) {
    let margin: CGFloat = 8
    let width = min(420, visibleFrame.width - margin * 2)
    let top = min(anchor.minY - 3, visibleFrame.maxY)
    let height = min(
      contentHeight + CleanerPopoverShape.pointerHeight, top - visibleFrame.minY - margin)
    let x = min(
      max(anchor.midX - width / 2, visibleFrame.minX + margin),
      visibleFrame.maxX - margin - width)
    frame = NSRect(x: x, y: top - height, width: width, height: height)
    pointerX = anchor.midX - x
  }
}

/// One outline keeps the pointer and the body in the same glass surface.
struct CleanerPopoverShape: Shape {
  static let pointerHeight: CGFloat = 12
  var pointerX: CGFloat?
  var cornerRadius: CGFloat = 22

  var animatableData: CGFloat {
    get { cornerRadius }
    set { cornerRadius = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let center = rect.minX + (pointerX ?? rect.width / 2)
    let sideRoom = max(0, min(center - rect.minX, rect.maxX - center))
    let radius = min(cornerRadius, sideRoom / 3, max(0, rect.height - Self.pointerHeight) / 2)
    let shoulder = min(26, max(2, sideRoom - radius - 2))
    let top = rect.minY + Self.pointerHeight
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + radius, y: top))
    path.addLine(to: CGPoint(x: center - shoulder, y: top))
    path.addCurve(
      to: CGPoint(x: center, y: rect.minY),
      control1: CGPoint(x: center - shoulder * 0.45, y: top),
      control2: CGPoint(x: center - shoulder * 0.16, y: rect.minY + Self.pointerHeight * 0.55))
    path.addCurve(
      to: CGPoint(x: center + shoulder, y: top),
      control1: CGPoint(x: center + shoulder * 0.16, y: rect.minY + Self.pointerHeight * 0.55),
      control2: CGPoint(x: center + shoulder * 0.45, y: top))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: top + radius),
      control: CGPoint(x: rect.maxX, y: top))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + radius, y: top),
      control: CGPoint(x: rect.minX, y: top))
    path.closeSubpath()
    return path
  }
}

@MainActor
final class CleanerPopoverPresentation: ObservableObject {
  @Published var isVisible: Bool

  init(isVisible: Bool = true) { self.isVisible = isVisible }
}

@MainActor
final class CleanerPopoverPanel: NSPanel {
  let presentation = CleanerPopoverPresentation(isVisible: false)
  var dismiss: (() -> Void)?
  private(set) var isPresented = false
  private var visibilityGeneration = 0
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func present() {
    guard !isPresented else { return }
    visibilityGeneration += 1
    isPresented = true
    ignoresMouseEvents = false
    animationBehavior = .none
    let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    // Lay out the hidden content first, then animate only its composited appearance.
    contentView?.layoutSubtreeIfNeeded()
    makeKeyAndOrderFront(nil)
    withAnimation(reducedMotion ? nil : .smooth(duration: 0.46, extraBounce: 0)) {
      presentation.isVisible = true
    }
  }

  func dismissAnimated() {
    guard isPresented else { return }
    isPresented = false
    visibilityGeneration += 1
    let generation = visibilityGeneration
    ignoresMouseEvents = true
    let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    withAnimation(
      reducedMotion ? nil : .smooth(duration: 0.36, extraBounce: 0), completionCriteria: .removed
    ) {
      presentation.isVisible = false
    } completion: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isPresented, self.visibilityGeneration == generation else { return }
        self.orderOut(nil)
        self.ignoresMouseEvents = false
      }
    }
  }

  override func cancelOperation(_ sender: Any?) {
    dismiss?()
  }
}
