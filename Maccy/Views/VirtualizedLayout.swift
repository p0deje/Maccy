import SwiftUI

// MARK: - Custom Layout for Virtualized Lists
// Based on: https://nilcoalescing.com/blog/CustomLazyListInSwiftUI
//
// This implementation solves the scrolling jump problem by:
// 1. Using precise positioning via the Layout protocol
// 2. Recycling views with fragment IDs
// 3. Never changing the total height when loading new pages
// 4. Rendering placeholders for unloaded items
//
// Image items render taller than text items, so total height and per-item
// y-offsets are computed from a sorted list of indices whose items contain
// an image. The layout keeps a prefix-sum cache for O(log n) placement.

/// Custom layout for virtualized list that maintains stable scroll positions.
/// Calculates total height upfront and positions items at exact offsets,
/// accounting for items with images having a different height than text items.
struct VirtualizedLayout: Layout {
  let textItemHeight: CGFloat
  let imageItemHeight: CGFloat
  let totalItemCount: Int
  let loadedRange: Range<Int>
  /// Sorted ascending list of item indices (within the full ordered list) whose
  /// items have an image. Used to compute exact y-offsets for each row.
  let imageItemIndices: [Int]

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 0
    let imageCount = min(imageItemIndices.count, totalItemCount)
    let textCount = max(0, totalItemCount - imageCount)
    let height = CGFloat(textCount) * textItemHeight + CGFloat(imageCount) * imageItemHeight
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard !subviews.isEmpty else { return }

    let width = proposal.width ?? bounds.width

    for subview in subviews {
      let rowIndex = subview[RowIndexKey.self]
      let (imagesBefore, isImage) = imageStats(forRowIndex: rowIndex)
      let textBefore = rowIndex - imagesBefore
      let yOffset = CGFloat(textBefore) * textItemHeight + CGFloat(imagesBefore) * imageItemHeight
      let rowHeight = isImage ? imageItemHeight : textItemHeight

      subview.place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + yOffset),
        proposal: ProposedViewSize(width: width, height: rowHeight)
      )
    }
  }

  /// Returns the number of image items strictly before `rowIndex` and whether
  /// `rowIndex` itself is an image item. Uses binary search on the sorted
  /// `imageItemIndices` array.
  private func imageStats(forRowIndex rowIndex: Int) -> (imagesBefore: Int, isImage: Bool) {
    var lower = 0
    var upper = imageItemIndices.count
    while lower < upper {
      let mid = (lower + upper) / 2
      if imageItemIndices[mid] < rowIndex {
        lower = mid + 1
      } else {
        upper = mid
      }
    }
    let isImage = lower < imageItemIndices.count && imageItemIndices[lower] == rowIndex
    return (lower, isImage)
  }
}

/// Layout value key to pass row index information to the layout
struct RowIndexKey: LayoutValueKey {
  static let defaultValue: Int = 0
}

extension View {
  func rowIndex(_ index: Int) -> some View {
    layoutValue(key: RowIndexKey.self, value: index)
  }
}

/// Placeholder view for unloaded items - lightweight and doesn't trigger loads
struct PlaceholderItemView: View {
  var body: some View {
    Color.clear
      .frame(height: 1)
  }
}

/// Determines the type of item to render
enum VirtualizedItemType {
  case loaded(HistoryItemDecorator)
  case placeholder
  case sentinel(onAppear: () -> Void, onDisappear: () -> Void)
}

/// A single item in the virtualized list with proper positioning
struct VirtualizedItem: View {
  let index: Int
  let type: VirtualizedItemType
  let fragmentID: String

  var body: some View {
    Group {
      switch type {
      case .loaded(let item):
        HistoryItemView(item: item, previous: nil, next: nil, index: index)
      case .placeholder:
        PlaceholderItemView()
      case .sentinel(let onAppear, let onDisappear):
        Color.clear
          .frame(height: 0)
          .onAppear { onAppear() }
          .onDisappear { onDisappear() }
      }
    }
    .rowIndex(index)
    .id(fragmentID)
  }
}

/// Container view that manages the virtualized list with custom layout
struct VirtualizedListContainer: View {
  let totalCount: Int
  let textItemHeight: CGFloat
  let imageItemHeight: CGFloat
  let imageItemIndices: [Int]
  let loadedRange: Range<Int>
  let loadedItems: [HistoryItemDecorator]
  let maxVisibleItems: Int
  let onLoadPrevious: () -> Void
  let onLoadNext: () -> Void

  @State private var hasTriggeredLoadPrevious = false
  @State private var hasTriggeredLoadNext = false

  var body: some View {
    ScrollView {
      VirtualizedLayout(
        textItemHeight: textItemHeight,
        imageItemHeight: imageItemHeight,
        totalItemCount: totalCount,
        loadedRange: loadedRange,
        imageItemIndices: imageItemIndices
      ) {
        // Build the complete set of items to render
        ForEach(itemsToRender, id: \.fragmentID) { item in
          item
        }
      }
    }
  }

  /// Calculate which items should be rendered
  /// Renders loaded items plus small buffers of placeholders on each side
  private var itemsToRender: [VirtualizedItem] {
    var items: [VirtualizedItem] = []

    // Add sentinel at top if there are items to load before
    if loadedRange.lowerBound > 0 {
      let sentinelIndex = max(0, loadedRange.lowerBound - 1)
      items.append(VirtualizedItem(
        index: sentinelIndex,
        type: .sentinel(
          onAppear: {
            if !hasTriggeredLoadPrevious {
              hasTriggeredLoadPrevious = true
              onLoadPrevious()
            }
          },
          onDisappear: {
            hasTriggeredLoadPrevious = false
          }
        ),
        fragmentID: "sentinel-before"
      ))
    }

    // Render all loaded items
    for (offset, item) in loadedItems.enumerated() {
      let index = loadedRange.lowerBound + offset
      items.append(VirtualizedItem(
        index: index,
        type: .loaded(item),
        fragmentID: fragmentID(for: index)
      ))
    }

    // Add sentinel at bottom if there are items to load after
    if loadedRange.upperBound < totalCount {
      let sentinelIndex = loadedRange.upperBound
      items.append(VirtualizedItem(
        index: sentinelIndex,
        type: .sentinel(
          onAppear: {
            if !hasTriggeredLoadNext {
              hasTriggeredLoadNext = true
              onLoadNext()
            }
          },
          onDisappear: {
            hasTriggeredLoadNext = false
          }
        ),
        fragmentID: "sentinel-after"
      ))
    }

    return items
  }

  /// Calculate fragment ID for view recycling
  private func fragmentID(for index: Int) -> String {
    let fragmentIndex = index % maxVisibleItems
    return "row-\(fragmentIndex)"
  }
}
