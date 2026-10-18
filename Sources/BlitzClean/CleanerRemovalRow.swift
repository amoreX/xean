import SwiftUI

/// A successful deletion is presented separately from the filesystem operation.
struct CleanerRemovalRow<Content: View>: View {
  let removed: Bool
  var onFinished: () -> Void = {}
  @ViewBuilder var content: () -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var fill: CGFloat = 0
  @State private var departing = false
  @State private var height: CGFloat = 1

  var body: some View {
    CleanerDisclosureLayout(progress: height) {
      content()
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.red.opacity(0.16))
            .scaleEffect(x: fill, y: 1, anchor: .center)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: fill)
        }
        .opacity(departing ? 0 : 1)
        .offset(x: departing && !reduceMotion ? 18 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: departing)
    }
    .clipped()
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: height)
    .allowsHitTesting(!removed)
    .accessibilityHidden(removed)
    .task(id: removed) {
      guard removed else {
        fill = 0
        departing = false
        height = 1
        return
      }
      if !reduceMotion {
        fill = 1
        do { try await Task.sleep(for: .milliseconds(440)) } catch { return }
        departing = true
        do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
        height = 0
        do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
      } else {
        height = 0
      }
      guard !Task.isCancelled else { return }
      onFinished()
    }
  }
}
