import Foundation

struct UIState {
    var width: Int
    var height: Int
    var bannerHeight: Int
    var footerHeight: Int

    var contentTopRow: Int { bannerHeight + 2 }
    var contentBottomRow: Int { max(contentTopRow, height - footerHeight - 2) }
    var inputRow: Int { max(contentTopRow, height - footerHeight - 1) }

    var contentHeight: Int {
        max(3, contentBottomRow - contentTopRow + 1)
    }
}
