import Foundation

enum DateTimeUtils {

    // MARK: - Time Conversion

    /// Converts "HH:MM" to minutes since midnight.
    static func timeToMinutes(_ timeStr: String) -> Int {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Converts minutes since midnight to "HH:MM".
    static func minutesToTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Formatting

    /// Formats "HH:MM" (24h) to "H:MM AM/PM".
    static func formatTime(_ timeStr: String) -> String {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return timeStr }
        let hours = parts[0]
        let minutes = parts[1]
        let period = hours >= 12 ? "PM" : "AM"
        let displayHours = hours > 12 ? hours - 12 : (hours == 0 ? 12 : hours)
        return "\(displayHours):\(String(format: "%02d", minutes)) \(period)"
    }

    /// Formats a duration in minutes to human-readable: "45m" or "2h 30m".
    static func formatElapsed(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }

    /// Formats a time range for display on a calendar block.
    /// Uses en-dash separator. If start and end share AM/PM, omits period from start.
    /// When isTask is true, wraps in parentheses.
    static func formatBlockTimeRange(start startStr: String, end endStr: String, isTask: Bool) -> String {
        let startParts = startStr.split(separator: ":").compactMap { Int($0) }
        let endParts = endStr.split(separator: ":").compactMap { Int($0) }
        guard startParts.count == 2, endParts.count == 2 else { return "" }

        let startH = startParts[0], startM = startParts[1]
        let endH = endParts[0], endM = endParts[1]

        let startPeriod = startH >= 12 ? "pm" : "am"
        let endPeriod = endH >= 12 ? "pm" : "am"
        let startDisplay = startH > 12 ? startH - 12 : (startH == 0 ? 12 : startH)
        let endDisplay = endH > 12 ? endH - 12 : (endH == 0 ? 12 : endH)

        let startTime = "\(startDisplay):\(String(format: "%02d", startM))"
        let endTime = "\(endDisplay):\(String(format: "%02d", endM))\(endPeriod)"

        let range: String
        if startPeriod == endPeriod {
            range = "\(startTime)\u{2013}\(endTime)"
        } else {
            range = "\(startTime)\(startPeriod)\u{2013}\(endTime)"
        }

        return isTask ? "(\(range))" : range
    }

    // MARK: - Current Time

    /// Returns current local time as minutes since midnight.
    static func currentTimeMinutes() -> Int {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        return hour * 60 + minute
    }

    /// Returns today's date as "YYYY-MM-DD".
    static func todayStr() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Date Arithmetic

    /// Adds days to a "YYYY-MM-DD" date string. Uses noon to avoid DST issues.
    static func addDays(_ dateStr: String, days: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateStr + "T12:00:00") else { return dateStr }
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: date) else { return dateStr }
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "yyyy-MM-dd"
        return outFormatter.string(from: newDate)
    }

    /// Returns a Date object from a "YYYY-MM-DD" string (at noon to avoid DST issues).
    static func dateFromStr(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr + "T12:00:00")
    }

    // MARK: - Date Header Formatting

    /// "Saturday, February 21"
    static func formatDateHeader(_ dateStr: String) -> String {
        guard let date = dateFromStr(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }

    /// "Sat 21"
    static func formatShortDateHeader(_ dateStr: String) -> String {
        guard let date = dateFromStr(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEd")
        return formatter.string(from: date)
    }

    /// "Sat, Feb 21"
    static func formatDateHeaderCompact(_ dateStr: String) -> String {
        guard let date = dateFromStr(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEMMMd")
        return formatter.string(from: date)
    }

    // MARK: - ID Generation

    /// Generates a unique ID matching web's Date.now() (milliseconds since epoch).
    static func generateId() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}
