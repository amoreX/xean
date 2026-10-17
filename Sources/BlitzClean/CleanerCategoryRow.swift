import SwiftUI

struct CleanerCategoryRow: View {
  @ObservedObject var model: CleanerModel
  let category: CleanerCategory
  @State private var expanded = false
  private let colors = BlitzPalette.paper

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Toggle(
          "Include \(category.title) in Clean",
          isOn: Binding(
            get: { model.preferences.categories.contains(category) },
            set: { selected in
              if selected {
                model.preferences.categories.insert(category)
              } else {
                model.preferences.categories.remove(category)
              }
              model.sounds.play(.toggle)
            })
        ).toggleStyle(BlitzCheckboxStyle(showsLabel: false)).frame(width: 18)
          .disabled(model.isBusy)
        Button {
          if !expanded { model.prepareCategory(category) }
          expanded.toggle()
          model.sounds.play(.toggle)
          if expanded {
            Task { await model.loadCategory(category) }
          }
        } label: {
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              Text(category.title).font(BlitzType.rowTitle)
              Text(category.detail).font(BlitzType.caption).foregroundStyle(colors.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            CleanerCategoryIndicator(
              expanded: expanded, loading: model.loadingCategory == category)
          }.frame(maxWidth: .infinity, minHeight: 34).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .disabled(model.isBusy && model.loadingCategory != category && !expanded)
          .accessibilityLabel("\(category.title) items")
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
      }.padding(.vertical, 5).cleanerScrollItem()
      CleanerDisclosureReveal(
        expanded: expanded, revision: model.categoryScans[category]?.scannedAt
      ) {
        inventory.padding(.leading, 28).padding(.bottom, 8)
      }
    }
  }

  private var inventory: some View {
    Group {
      if let report = model.categoryScans[category] {
        inventoryRows(report).transition(.identity)
      } else {
        Text(model.stopRequested ? "Check stopped. Reopen to try again." : "Checking…")
          .font(BlitzType.caption)
          .foregroundStyle(colors.secondaryText).cleanerScrollItem().transition(.identity)
      }
    }
  }

  private func inventoryRows(_ report: CleanerScan) -> some View {
    let items = report.visibleItems
    let kept = report.visibleKept
    return VStack(alignment: .leading, spacing: 8) {
      if items.isEmpty && kept.isEmpty {
        Text("No items 50 MB or larger.").font(BlitzType.caption)
          .foregroundStyle(colors.secondaryText).cleanerScrollItem()
      }
      VStack(alignment: .leading, spacing: 10) {
        ForEach(items) { item in
          CleanerInventoryItem(model: model, item: item).cleanerScrollItem()
        }
        ForEach(kept) { item in
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
              Label(item.name, systemImage: "lock").font(BlitzType.body)
              Spacer(minLength: 8)
              if let bytes = item.bytes { Text(ByteText.compact(bytes)).monospacedDigit() }
            }
            Text(CleanerInventoryItem.shortPath(item.path)).lineLimit(2).truncationMode(.middle)
            Text(item.reason)
          }.font(BlitzType.caption).foregroundStyle(colors.secondaryText).cleanerScrollItem()
        }
      }
    }
  }

}

private struct CleanerCategoryIndicator: View {
  let expanded: Bool
  let loading: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Image(systemName: "chevron.right")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BlitzPalette.paper.secondaryText)
        .rotationEffect(.degrees(expanded ? 90 : 0))
      if loading {
        ProgressView().controlSize(.mini).frame(width: 12, height: 12).offset(x: -16)
      }
    }.frame(width: 38)
      .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: expanded)
  }
}

struct CleanerDisclosureReveal<Content: View>: View {
  let expanded: Bool
  var revision: Date? = nil
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // Keep intrinsic layout stable while the visible height changes, including on a refresh.
    CleanerDisclosureLayout(progress: expanded ? 1 : 0) { content }
      .clipped()
      .opacity(expanded ? 1 : 0)
      .allowsHitTesting(expanded)
      .accessibilityHidden(!expanded)
      .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: expanded)
      .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: revision)
  }
}

private struct CleanerDisclosureLayout: Layout {
  var progress: CGFloat
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    let size = content.sizeThatFits(.init(width: proposal.width, height: nil))
    return CGSize(width: size.width, height: size.height * progress)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: .init(width: bounds.width, height: nil))
  }
}

private struct CleanerInventoryItem: View {
  @ObservedObject var model: CleanerModel
  let item: CleanerItem
  private let colors = BlitzPalette.paper

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(item.category == .docker ? "Unused build cache" : item.name)
            .font(BlitzType.body).lineLimit(2)
          if let branch = item.branch {
            Text(branch).font(BlitzType.caption).foregroundStyle(colors.secondaryText)
          }
          Text(Self.shortPath(item.path)).font(BlitzType.caption)
            .foregroundStyle(colors.secondaryText).lineLimit(2).truncationMode(.middle)
            .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(ByteText.compact(item.bytes)).font(BlitzType.caption).monospacedDigit()
            .foregroundStyle(colors.secondaryText)
          if model.removingItemID == item.id {
            ProgressView().controlSize(.mini).accessibilityLabel("Deleting \(item.name)")
          } else {
            Button("Delete", role: .destructive) { Task { await model.deleteItem(item) } }
              .blitzButton(.quiet).controlSize(.small).disabled(model.isBusy)
              .accessibilityLabel("Delete \(item.name)")
          }
        }
      }
      if let failure = model.itemFailures[item.id] {
        Text("Couldn’t delete: \(failure)").font(BlitzType.caption)
          .foregroundStyle(colors.secondaryText).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  static func shortPath(_ path: String) -> String {
    path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
  }
}
