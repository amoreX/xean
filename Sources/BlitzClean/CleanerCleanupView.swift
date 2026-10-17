import SwiftUI

struct CleanerCleanupView: View {
  @ObservedObject var model: CleanerModel
  let cleanup: CleanerCleanup
  var onClose: () -> Void

  var body: some View {
    if cleanup.phase == .finished, let result = cleanup.result {
      completion(result)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text(cleanup.phase == .scanning ? "Checking selected items…" : "Cleaning…")
            .font(.headline)
          Spacer()
          if cleanup.phase == .removing {
            Text("\(cleanup.removedIDs.count) / \(cleanup.items.count)")
              .foregroundStyle(.secondary).monospacedDigit()
          }
        }.padding(.horizontal, 18).padding(.vertical, 16)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(cleanup.items) { item in
              CleanerDisclosureReveal(expanded: !cleanup.removedIDs.contains(item.id)) {
                itemRow(item).padding(.vertical, 10).cleanerScrollItem()
              }
            }
          }.padding(.horizontal, 18).padding(.vertical, 18)
        }.cleanerScrollViewport()
      }.frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private func completion(_ result: CleanerOutcome) -> some View {
    let complete = result.kept == 0
    let nothingToClean = cleanup.items.isEmpty
    return VStack(spacing: 0) {
      Spacer(minLength: 24)
      Image(systemName: complete ? "checkmark.circle" : "exclamationmark.circle")
        .font(.system(size: 36, weight: .light))
        .foregroundStyle(complete ? Color.green : Color.orange)
        .accessibilityHidden(true)
        .padding(.bottom, 16)
      Text(nothingToClean ? "Nothing to clean" : complete ? "All clean" : "Cleanup finished")
        .font(.system(size: 22, weight: .semibold))
        .padding(.bottom, 8)
      if nothingToClean {
        Text("No eligible items in the selected categories.")
          .foregroundStyle(.secondary)
      } else {
        Text("\(ByteText.full(result.bytes)) removed")
          .font(.system(size: 17, weight: .medium)).monospacedDigit()
          .padding(.bottom, 4)
        Text(
          "\(result.removed) \(result.removed == 1 ? "item" : "items") removed"
            + (result.kept > 0 ? " · \(result.kept) kept" : "")
        )
        .foregroundStyle(.secondary)
      }
      if cleanup.protectedCount > 0 {
        Text(
          "\(cleanup.protectedCount) protected \(cleanup.protectedCount == 1 ? "item" : "items") kept"
        )
        .foregroundStyle(.secondary).padding(.top, 4)
      }
      if !complete {
        ScrollView {
          VStack(spacing: 16) {
            ForEach(cleanup.items.filter { !cleanup.removedIDs.contains($0.id) }) { item in
              itemRow(item).cleanerScrollItem()
            }
          }.padding(.vertical, 18)
        }.cleanerScrollViewport().frame(maxHeight: 200).padding(.top, 16)
      }
      Spacer(minLength: 24)
      HStack {
        Spacer()
        Button("Done", action: onClose).cleanerButton(prominent: true)
          .keyboardShortcut(.defaultAction)
      }.padding(.bottom, 14)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, 18)
    .accessibilityIdentifier("cleaner-result")
  }

  private func itemRow(_ item: CleanerItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
        Text(
          item.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
        if let failure = model.itemFailures[item.id] {
          Text(failure).font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Text(ByteText.compact(item.bytes)).font(.caption)
        .foregroundStyle(.secondary).monospacedDigit()
    }.multilineTextAlignment(.leading)
  }
}
