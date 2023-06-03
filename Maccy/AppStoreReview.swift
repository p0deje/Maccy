import StoreKit

class AppStoreReview {
  class func ask() {
    UserDefaults.standard.numberOfUsages += 1
    guard UserDefaults.standard.numberOfUsages > 50 else { return }

    let today = Date()
    let lastReviewRequestDate = UserDefaults.standard.lastReviewRequestedAt
    guard let minimumRequestDate = Calendar.current.date(byAdding: .month, value: 1, to: lastReviewRequestDate),
          today > minimumRequestDate else {
      return
    }

    UserDefaults.standard.lastReviewRequestedAt = today

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      SKStoreReviewController.requestReview()
    }
  }
}
