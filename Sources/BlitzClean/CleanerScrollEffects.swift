import SwiftUI

extension View {
  func cleanerScrollItem() -> some View {
    modifier(CleanerScrollItem())
  }

  func cleanerScrollViewport() -> some View {
    modifier(CleanerScrollViewport())
  }
}

private struct CleanerScrollItem: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    let keepsStill = reduceMotion || contrast == .increased
    content.visualEffect { effect, geometry in
      let frame = geometry.frame(in: .scrollView(axis: .vertical))
      let height = geometry.bounds(of: .scrollView(axis: .vertical))?.height ?? .infinity
      // Follow the actual scroll position, without animating or changing the row's layout.
      let visible = min(frame.maxY - 12, height - 12 - frame.minY)
      let fraction = 1 - min(1, max(0, visible / max(1, min(frame.height, 64))))
      let edge = keepsStill ? 0 : fraction * fraction * (3 - 2 * fraction)
      return
        effect
        .scaleEffect(1 - 0.045 * edge)
        .blur(radius: 1.4 * edge)
        .opacity(1 - 0.25 * edge)
    }
  }
}

private struct CleanerScrollViewport: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content
      .scrollIndicators(.never)
      .mask {
        if contrast == .increased {
          Rectangle()
        } else {
          VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
              .frame(height: 18)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
              .frame(height: 14)
          }
        }
      }
  }
}
