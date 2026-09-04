import SwiftUI

struct DaySeparatorView: View {
  let date: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(Self.label(for: date))
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Popup.horizontalPadding + 5)
        .padding(.top, Popup.verticalSeparatorPadding)

      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)
    }
    .accessibilityAddTraits(.isHeader)
    .allowsHitTesting(false)
  }

  static func label(
    for date: Date,
    now: Date = .now,
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
      let formatter = DateFormatter()
      formatter.doesRelativeDateFormatting = true
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      formatter.calendar = calendar
      formatter.locale = locale
      formatter.timeZone = calendar.timeZone
      return formatter.string(from: date)
    }

    var style = Date.FormatStyle()
      .weekday(.wide)
      .day()
      .month(.abbreviated)
      .locale(locale)
    if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
      style = style.year()
    }
    return date.formatted(style)
  }
}
