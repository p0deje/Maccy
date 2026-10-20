import SwiftUI

// MARK: - Virtualized list geometry
//
// Based on: https://nilcoalescing.com/blog/CustomLazyListInSwiftUI
//
// The list renders a spacer with the exact height of the full history and
// positions only the rows near the viewport at their absolute offsets. The
// scroll offset is observed and mapped to a row range, which the data layer
// translates into page requests. Because the content size never changes
// while scrolling, the scrollbar reflects the entire history and there are
// no jumps when pages load.

/// Pure row geometry for a virtualized list whose rows come in two heights:
/// a regular height and a tall height (image rows in Maccy's case).
/// All lookups are O(log n) via binary search over the sorted tall indices.
nonisolated struct VirtualListMetrics: Equatable {
  var rowHeight: CGFloat
  var tallRowHeight: CGFloat
  var totalCount: Int
  /// Sorted ascending indices of rows using `tallRowHeight`.
  var tallRowIndices: [Int]

  var totalHeight: CGFloat {
    // Only count tall indices that fall inside the list; the indices can
    // briefly be stale relative to totalCount while a refresh propagates.
    let tallCount = tallStats(for: totalCount).before
    return CGFloat(totalCount - tallCount) * rowHeight + CGFloat(tallCount) * tallRowHeight
  }

  func height(ofRow row: Int) -> CGFloat {
    tallStats(for: row).isTall ? tallRowHeight : rowHeight
  }

  func offset(ofRow row: Int) -> CGFloat {
    let tallBefore = tallStats(for: row).before
    return CGFloat(row - tallBefore) * rowHeight + CGFloat(tallBefore) * tallRowHeight
  }

  /// The row whose vertical extent contains `position`, clamped to valid rows.
  func row(atOffset position: CGFloat) -> Int {
    guard totalCount > 0, position > 0 else { return 0 }

    var lower = 0
    var upper = totalCount - 1
    while lower < upper {
      let mid = (lower + upper + 1) / 2
      if offset(ofRow: mid) <= position {
        lower = mid
      } else {
        upper = mid - 1
      }
    }
    return lower
  }

  /// Rows intersecting the vertical viewport `bounds`.
  func rows(in bounds: ClosedRange<CGFloat>) -> Range<Int> {
    guard totalCount > 0, bounds.upperBound > 0 else { return 0..<0 }

    let first = row(atOffset: bounds.lowerBound)
    let last = row(atOffset: bounds.upperBound)
    return first ..< min(totalCount, last + 1)
  }

  /// Number of tall rows strictly before `row`, and whether `row` is tall.
  private func tallStats(for row: Int) -> (before: Int, isTall: Bool) {
    var lower = 0
    var upper = tallRowIndices.count
    while lower < upper {
      let mid = (lower + upper) / 2
      if tallRowIndices[mid] < row {
        lower = mid + 1
      } else {
        upper = mid
      }
    }
    let isTall = lower < tallRowIndices.count && tallRowIndices[lower] == row
    return (lower, isTall)
  }
}

/// A vertically virtualized scroll view: only rows near the viewport (plus a
/// small overscan) exist as views, absolutely positioned inside a spacer of
/// the full list height. Rows are addressed by index, so the view is
/// independent of the item type and data source.
struct VirtualizedList<Row: View>: View {
  var metrics: VirtualListMetrics
  var overscan: Int = 10
  /// Row to bring into view (keyboard navigation). Reset via the callback.
  var scrollTargetRow: Int?
  var onVisibleRowsChanged: (Range<Int>) -> Void
  var onScrollTargetHandled: () -> Void = {}
  @ViewBuilder var row: (Int) -> Row

  /// The scroll offset changes on every frame while scrolling. It is kept
  /// outside of SwiftUI state, so the view only updates when the visible
  /// rows change.
  @State private var scroll = ScrollState()
  @State private var visibleRows: Range<Int> = 0..<0

  private static var coordinateSpace: String { "virtualizedList" }

  private var renderedRows: Range<Int> {
    guard metrics.totalCount > 0 else { return 0..<0 }

    let visible = visibleRows
    let lower = max(0, visible.lowerBound - overscan)
    let upper = min(metrics.totalCount, visible.upperBound + overscan)
    return lower ..< max(lower, upper)
  }

  private var rowIndices: [Int] {
    var indices = Array(renderedRows)
    if let target = scrollTargetRow, !renderedRows.contains(target), (0..<metrics.totalCount).contains(target) {
      indices.append(target)
    }
    return indices
  }

  var body: some View {
    GeometryReader { viewport in
      ScrollViewReader { proxy in
        ScrollView {
          VirtualRowsLayout(metrics: metrics) {
            ForEach(rowIndices, id: \.self) { index in
              row(index)
                .virtualRowIndex(index)
                .id(index)
            }
          }
          .frame(maxWidth: .infinity)
          .background {
            GeometryReader { content in
              Color.clear.preference(
                key: VirtualizedListOffsetKey.self,
                value: -content.frame(in: .named(Self.coordinateSpace)).minY
              )
            }
          }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(VirtualizedListOffsetKey.self) { offset in
          scroll.offset = offset
          updateVisibleRows()
        }
        .task(id: scrollTargetRow) {
          guard let target = scrollTargetRow else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          proxy.scrollTo(target)
          onScrollTargetHandled()
        }
      }
      .onAppear {
        scroll.viewportHeight = viewport.size.height
        updateVisibleRows()
      }
      .onChange(of: viewport.size.height) { _, height in
        scroll.viewportHeight = height
        updateVisibleRows()
      }
    }
    .onAppear { onVisibleRowsChanged(visibleRows) }
    .onChange(of: metrics) { updateVisibleRows() }
    .onChange(of: visibleRows) { _, rows in onVisibleRowsChanged(rows) }
  }

  private func updateVisibleRows() {
    let rows = metrics.rows(in: scroll.offset...(scroll.offset + max(scroll.viewportHeight, 0)))
    if rows != visibleRows {
      visibleRows = rows
    }
  }
}

/// Reference storage for scroll geometry. Writes to it do not invalidate views.
private final class ScrollState {
  var offset: CGFloat = 0
  var viewportHeight: CGFloat = 0
}

/// Places each row at its exact offset inside a container that always has
/// the full height of the list, so the scrollbar reflects the entire history
/// and loading pages never moves already-visible content. Rows get real
/// layout frames (unlike `.offset`), which keeps `ScrollViewReader.scrollTo`
/// and hit testing working.
private nonisolated struct VirtualRowsLayout: Layout {
  var metrics: VirtualListMetrics

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 0, height: metrics.totalHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      let index = subview[VirtualRowIndexKey.self]
      subview.place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + metrics.offset(ofRow: index)),
        proposal: ProposedViewSize(width: bounds.width, height: metrics.height(ofRow: index))
      )
    }
  }
}

/// Layout value key carrying each row's index into the layout.
private nonisolated struct VirtualRowIndexKey: LayoutValueKey {
  static let defaultValue: Int = 0
}

extension View {
  fileprivate func virtualRowIndex(_ index: Int) -> some View {
    layoutValue(key: VirtualRowIndexKey.self, value: index)
  }
}

private nonisolated struct VirtualizedListOffsetKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
