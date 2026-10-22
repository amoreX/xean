import SwiftUI

struct CleanerCategoryRow: View {
  @ObservedObject var model: CleanerModel
  let category: CleanerCategory
  @State private var expanded = false

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
        ).toggleStyle(.checkbox).labelsHidden().frame(width: 18)
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
              Text(category.detail).font(BlitzType.caption).foregroundStyle(.secondary)
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
        CleanerInventoryList(model: model, report: report).transition(.identity)
      } else {
        Text(model.stopRequested ? "Check stopped. Reopen to try again." : "Checking…")
          .font(BlitzType.caption)
          .foregroundStyle(.secondary).cleanerScrollItem().transition(.identity)
      }
    }
  }

}

struct CleanerInventoryList: View {
  @ObservedObject var model: CleanerModel
  let report: CleanerScan
  @State private var items: [CleanerItem]

  init(model: CleanerModel, report: CleanerScan) {
    self.model = model
    self.report = report
    _items = State(initialValue: report.visibleItems)
  }

  var body: some View {
    let kept = report.visibleKept
    return VStack(alignment: .leading, spacing: 8) {
      if let summary = report.inventorySummary {
        Text(summary).font(BlitzType.caption)
          .foregroundStyle(.secondary).cleanerScrollItem()
      }
      ForEach(Array(Set(report.notes)).sorted(), id: \.self) { note in
        Label(
          note.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "info.circle"
        )
        .font(BlitzType.caption).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true
        )
        .cleanerScrollItem()
      }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(items) { item in
          CleanerRemovalRow(
            removed: !report.visibleItems.contains { $0.id == item.id }
              && model.removedItemIDs.contains(item.id),
            onFinished: { items.removeAll { $0.id == item.id } }
          ) {
            CleanerInventoryItem(model: model, item: item)
              .padding(.vertical, 5).cleanerScrollItem()
          }
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
          }.font(BlitzType.caption).foregroundStyle(.secondary)
            .padding(.vertical, 5).cleanerScrollItem()
        }
      }
    }
    .onChange(of: report.visibleItems.map(\.id)) { _, _ in items = report.visibleItems }
    .onChange(of: report.scannedAt) { _, _ in items = report.visibleItems }
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
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(expanded ? 90 : 0))
      if loading {
        ProgressView().controlSize(.mini).frame(width: 12, height: 12).offset(x: -16)
      }
    }.frame(width: 38)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
  }
}

struct CleanerDisclosureReveal<Content: View>: View {
  let expanded: Bool
  let revision: Date?
  let content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mounted: Bool
  @State private var progress: CGFloat

  init(expanded: Bool, revision: Date? = nil, @ViewBuilder content: () -> Content) {
    self.expanded = expanded
    self.revision = revision
    self.content = content()
    _mounted = State(initialValue: expanded)
    _progress = State(initialValue: expanded ? 1 : 0)
  }

  var body: some View {
    CleanerDisclosureLayout(progress: progress) {
      if mounted { content.transaction { $0.animation = nil } }
    }
    .clipped()
    .allowsHitTesting(expanded)
    .accessibilityHidden(!expanded)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: revision)
    .onChange(of: expanded) { _, expanded in
      if expanded { mounted = true }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18), completionCriteria: .removed) {
        progress = expanded ? 1 : 0
      } completion: {
        // Unmount hidden native controls so they cannot retain focus or accessibility entries.
        if progress == 0 { mounted = false }
      }
    }
  }
}

struct CleanerDisclosureLayout: Layout {
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

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(item.category == .docker ? "Unused build cache" : item.name)
            .font(BlitzType.body).lineLimit(2)
          if let branch = item.branch {
            Text(branch).font(BlitzType.caption).foregroundStyle(.secondary)
          }
          Text(Self.shortPath(item.path)).font(BlitzType.caption)
            .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(ByteText.compact(item.bytes)).font(BlitzType.caption).monospacedDigit()
            .foregroundStyle(.secondary)
          if model.removingItemIDs.contains(item.id) {
            ProgressView().controlSize(.mini).accessibilityLabel("Deleting \(item.name)")
          } else {
            Button("Delete", role: .destructive) { Task { await model.deleteItem(item) } }
              .buttonStyle(.borderless).controlSize(.small).disabled(model.isBusy)
              .accessibilityLabel("Delete \(item.name)")
          }
        }
      }
      if let failure = model.itemFailures[item.id] {
        Text("Couldn’t delete: \(failure)").font(BlitzType.caption)
          .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  static func shortPath(_ path: String) -> String {
    path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
  }
}
