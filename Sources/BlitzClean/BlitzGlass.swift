import AppKit
import LiquidGlass
import SwiftUI

private struct BlitzGlassEnabledKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var blitzGlassEnabled: Bool {
    get { self[BlitzGlassEnabledKey.self] }
    set { self[BlitzGlassEnabledKey.self] = newValue }
  }
}

/// Keep glass behind content so the package's tint does not override control colors.
struct BlitzGlassBackground: View {
  var radius: CGFloat = 20
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Group {
      if reduceTransparency || contrast == .increased {
        RoundedRectangle(cornerRadius: radius)
          .fill(BlitzPalette.paper.panel)
          .overlay {
            RoundedRectangle(cornerRadius: radius)
              .strokeBorder(
                contrast == .increased
                  ? BlitzPalette.paper.primaryText : BlitzPalette.paper.strongStroke,
                lineWidth: 1)
          }
      } else {
        Color.clear.liquidGlass(
          shape: .roundedRect(cornerRadius: radius), opacity: 0.7)
      }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}

extension View {
  func blitzGlassSurface(radius: CGFloat = 20) -> some View {
    background { BlitzGlassBackground(radius: radius) }
  }
}

/// Use the package's native glass button style while retaining the existing button actions and roles.
private struct BlitzGlassButton<Label: View>: View {
  let button: Button<Label>
  let emphasis: BlitzButtonEmphasis
  @Environment(\.blitzGlassEnabled) private var enabled
  @Environment(\.blitzPalette) private var palette
  @Environment(\.controlSize) private var controlSize
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  private var prominent: Bool { emphasis == .accent || emphasis == .emphasized }

  var body: some View {
    if enabled && emphasis != .quiet && !reduceTransparency && contrast != .increased {
      button
        .glassStyleButton(
          shape: .roundedRect(cornerRadius: 10),
          prominent: prominent, tint: palette.accent
        )
        .tint(prominent ? palette.accent : .white)
        .font(.system(size: BlitzControlMetrics.fontSize(controlSize), weight: .medium))
        .controlSize(controlSize == .regular ? .large : controlSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    } else {
      button.buttonStyle(BlitzButtonStyle(emphasis))
    }
  }
}

extension Button {
  @MainActor func blitzButton(_ emphasis: BlitzButtonEmphasis) -> some View {
    BlitzGlassButton(button: self, emphasis: emphasis)
  }
}

struct CleanerWindowBackdrop: View {
  var pointerX: CGFloat?
  var cornerRadius: CGFloat = 22
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let outline = CleanerPopoverShape(pointerX: pointerX, cornerRadius: cornerRadius)
    Group {
      if reduceTransparency || contrast == .increased {
        outline.fill(BlitzPalette.paper.canvas)
          .overlay {
            outline.stroke(BlitzPalette.paper.strongStroke, lineWidth: 1)
          }
      } else {
        ZStack {
          CleanerDesktopMaterial().clipShape(outline)
          if #available(macOS 26.0, *) {
            Color.clear.glassEffect(in: outline)
          } else {
            Color.clear.liquidGlass(shape: .roundedRect(cornerRadius: 0), opacity: 0.45)
              .clipShape(outline)
          }
        }
      }
    }.clipShape(outline).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
  }

}

private struct CleanerDesktopMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.blendingMode = .behindWindow
    view.material = .popover
    view.state = .active
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
