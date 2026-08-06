import Foundation

enum ResetTimeFormatter {
    static func string(fromMinutes minutes: Int) -> String {
        guard minutes > 0 else { return "resets soon" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0 ? "resets in \(hours)h \(mins)m" : "resets in \(hours)h"
        }
        return "resets in \(mins)m"
    }
}
