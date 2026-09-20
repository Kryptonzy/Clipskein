import Foundation

enum ClipExpirationPreset: String, CaseIterable, Identifiable, Sendable {
  case oneHour
  case endOfDay
  case oneDay
  case oneWeek
  case never

  var id: String { rawValue }

  var label: String {
    switch self {
    case .oneHour: "In 1 hour"
    case .endOfDay: "At end of day"
    case .oneDay: "In 24 hours"
    case .oneWeek: "In 7 days"
    case .never: "Never"
    }
  }

  func date(from now: Date = .now, calendar: Calendar = .current) -> Date? {
    switch self {
    case .oneHour: now.addingTimeInterval(60 * 60)
    case .endOfDay:
      calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    case .oneDay: now.addingTimeInterval(24 * 60 * 60)
    case .oneWeek: now.addingTimeInterval(7 * 24 * 60 * 60)
    case .never: nil
    }
  }
}
