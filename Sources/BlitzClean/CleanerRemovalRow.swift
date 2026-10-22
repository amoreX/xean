import SwiftUI

/// Successful removals disappear immediately; failures retain their row and reason.
struct CleanerRemovalRow<Content: View>: View {
  let removed: Bool
  var onFinished: () -> Void = {}
  @ViewBuilder var content: () -> Content

  var body: some View {
    Group {
      if !removed { content() }
    }
    .task(id: removed) {
      if removed { onFinished() }
    }
  }
}
