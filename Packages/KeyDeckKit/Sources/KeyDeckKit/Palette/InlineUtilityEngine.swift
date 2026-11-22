import Foundation

public struct InlineUtilityResult: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var insertText: String
    public var systemImage: String

    public init(title: String, subtitle: String, insertText: String, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.insertText = insertText
        self.systemImage = systemImage
    }
}

/// Pure Swift, crash-safe inline utilities for the Command Palette:
/// math calculator, percentage math, unit conversions, timezone lookup, generators, and symbols.
public enum InlineUtilityEngine {

    public static func evaluate(_ rawQuery: String, now: Date = Date()) -> InlineUtilityResult? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let lower = query.lowercased()

        if let generator = evaluateGeneratorOrSymbol(lower, now: now) {
            return generator
        }
        if let tz = evaluateTimezone(lower, now: now) {
            return tz
        }
        if let conversion = evaluateUnitConversion(lower) {
            return conversion
        }
        if let math = evaluateMath(query) {
            return math
        }
        return nil
    }

    // MARK: - Generators & Quick Symbols

    private static func evaluateGeneratorOrSymbol(_ lower: String, now: Date) -> InlineUtilityResult? {
        switch lower {
        case "uuid", "guid":
            let value = UUID().uuidString
            return InlineUtilityResult(title: value, subtitle: "Generate UUID v4", insertText: value, systemImage: "number")
        case "uuidl":
            let value = UUID().uuidString.lowercased()
            return InlineUtilityResult(title: value, subtitle: "Generate lowercase UUID", insertText: value, systemImage: "number")
        case "ts", "epoch", "unix":
            let value = String(Int(now.timeIntervalSince1970))
            return InlineUtilityResult(title: value, subtitle: "Unix timestamp (seconds)", insertText: value, systemImage: "clock")
        case "tsms", "epochms":
            let value = String(Int(now.timeIntervalSince1970 * 1000))
            return InlineUtilityResult(title: value, subtitle: "Unix timestamp (ms)", insertText: value, systemImage: "clock")
        case "iso":
            let formatter = ISO8601DateFormatter()
            let value = formatter.string(from: now)
            return InlineUtilityResult(title: value, subtitle: "ISO-8601 timestamp", insertText: value, systemImage: "calendar.badge.clock")
        case "now":
            let value = SnippetEngine.formatDateTime(now)
            return InlineUtilityResult(title: value, subtitle: "Current date & time", insertText: value, systemImage: "clock")
        case "time":
            let value = SnippetEngine.formatTime(now)
            return InlineUtilityResult(title: value, subtitle: "Current time", insertText: value, systemImage: "clock")
        case "shrug":
            let value = #"¯\_(ツ)_/¯"#
            return InlineUtilityResult(title: value, subtitle: "Insert shrug", insertText: value, systemImage: "face.smiling")
        case "arrow", "->":
            return InlineUtilityResult(title: "→", subtitle: "Right arrow symbol", insertText: "→", systemImage: "arrow.right")
        case "em", "---":
            return InlineUtilityResult(title: "—", subtitle: "Em dash", insertText: "—", systemImage: "minus")
        case "check":
            return InlineUtilityResult(title: "✓", subtitle: "Checkmark symbol", insertText: "✓", systemImage: "checkmark")
        case "bullet":
            return InlineUtilityResult(title: "•", subtitle: "Bullet symbol", insertText: "• ", systemImage: "list.bullet")
        case "cmd":
            return InlineUtilityResult(title: "⌘", subtitle: "Command symbol", insertText: "⌘", systemImage: "command")
        case "deg":
            return InlineUtilityResult(title: "°", subtitle: "Degree symbol", insertText: "°", systemImage: "thermometer.medium")
        default:
            return nil
        }
    }

    // MARK: - Timezone Lookup (e.g. "now utc", "now tokyo", "3pm est to cst")

    private static let timeZoneAliases: [String: (id: String, label: String)] = [
        "utc": ("UTC", "UTC"),
        "gmt": ("GMT", "GMT"),
        "est": ("America/New_York", "ET"),
        "edt": ("America/New_York", "ET"),
        "et": ("America/New_York", "ET"),
        "ny": ("America/New_York", "New York"),
        "nyc": ("America/New_York", "New York"),
        "cst": ("America/Chicago", "CT"),
        "cdt": ("America/Chicago", "CT"),
        "ct": ("America/Chicago", "CT"),
        "mst": ("America/Denver", "MT"),
        "mdt": ("America/Denver", "MT"),
        "mt": ("America/Denver", "MT"),
        "pst": ("America/Los_Angeles", "PT"),
        "pdt": ("America/Los_Angeles", "PT"),
        "pt": ("America/Los_Angeles", "PT"),
        "sf": ("America/Los_Angeles", "San Francisco"),
        "la": ("America/Los_Angeles", "Los Angeles"),
        "london": ("Europe/London", "London"),
        "uk": ("Europe/London", "London"),
        "cet": ("Europe/Paris", "CET"),
        "paris": ("Europe/Paris", "Paris"),
        "berlin": ("Europe/Berlin", "Berlin"),
        "tokyo": ("Asia/Tokyo", "Tokyo"),
        "jst": ("Asia/Tokyo", "JST"),
        "ist": ("Asia/Kolkata", "IST"),
        "sydney": ("Australia/Sydney", "Sydney"),
        "cdmx": ("America/Mexico_City", "CDMX")
    ]

    private static func evaluateTimezone(_ lower: String, now: Date) -> InlineUtilityResult? {
        let tokens = lower.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }

        // Pattern 1: "now <tz>" or "time <tz>"
        if (tokens[0] == "now" || tokens[0] == "time"),
           tokens.count == 2,
           let target = timeZoneAliases[tokens[1]],
           let tz = TimeZone(identifier: target.id) {
            let formatted = formatTime(now, timeZone: tz)
            let output = "\(formatted) \(target.label)"
            return InlineUtilityResult(
                title: output,
                subtitle: "Current time in \(target.label)",
                insertText: output,
                systemImage: "globe"
            )
        }

        // Pattern 2: "3pm est to cst" or "14:30 pst in est"
        if tokens.count == 4, (tokens[2] == "to" || tokens[2] == "in"),
           let srcInfo = timeZoneAliases[tokens[1]],
           let dstInfo = timeZoneAliases[tokens[3]],
           let srcTZ = TimeZone(identifier: srcInfo.id),
           let dstTZ = TimeZone(identifier: dstInfo.id),
           let sourceDate = parseClockTime(tokens[0], timeZone: srcTZ, referenceDate: now) {
            let converted = formatTime(sourceDate, timeZone: dstTZ)
            let output = "\(converted) \(dstInfo.label)"
            return InlineUtilityResult(
                title: output,
                subtitle: "\(tokens[0].uppercased()) \(srcInfo.label) → \(dstInfo.label)",
                insertText: output,
                systemImage: "globe"
            )
        }

        return nil
    }

    private static func parseClockTime(_ token: String, timeZone: TimeZone, referenceDate: Date) -> Date? {
        var cleaned = token.lowercased()
        let isPM = cleaned.hasSuffix("pm")
        let isAM = cleaned.hasSuffix("am")
        if isPM || isAM {
            cleaned = String(cleaned.dropLast(2))
        }

        let parts = cleaned.split(separator: ":")
        guard let hourRaw = Int(parts[0]) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? -1) : 0
        guard minute >= 0 && minute < 60 else { return nil }

        var hour = hourRaw
        if isPM {
            guard hour >= 1 && hour <= 12 else { return nil }
            if hour < 12 { hour += 12 }
        } else if isAM {
            guard hour >= 1 && hour <= 12 else { return nil }
            if hour == 12 { hour = 0 }
        } else {
            guard hour >= 0 && hour <= 23 else { return nil }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    private static func formatTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Unit Conversions (e.g. "72f to c", "10 km to mi", "180 lb in kg")

    private static func evaluateUnitConversion(_ lower: String) -> InlineUtilityResult? {
        // Normalize "72f to c" -> "72 f to c"
        let pattern = #"^([+-]?\d+(?:\.\d+)?)\s*([a-z]+)\s+(?:to|in)\s+([a-z]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numRange = Range(match.range(at: 1), in: lower),
              let fromRange = Range(match.range(at: 2), in: lower),
              let toRange = Range(match.range(at: 3), in: lower),
              let value = Double(lower[numRange]) else {
            return nil
        }

        let fromUnit = String(lower[fromRange])
        let toUnit = String(lower[toRange])

        // Temperature
        if let temp = convertTemperature(value: value, from: fromUnit, to: toUnit) {
            let text = "\(formatNumber(temp.value))\(temp.symbol)"
            return InlineUtilityResult(
                title: text,
                subtitle: "\(formatNumber(value))\(fromUnit.uppercased()) → \(toUnit.uppercased())",
                insertText: text,
                systemImage: "thermometer.medium"
            )
        }

        // Linear-factor unit families
        let families: [[String: (factorToBase: Double, label: String)]] = [
            // Length (base: meters)
            [
                "m": (1, "m"), "meter": (1, "m"), "meters": (1, "m"),
                "km": (1000, "km"), "cm": (0.01, "cm"), "mm": (0.001, "mm"),
                "mi": (1609.344, "mi"), "mile": (1609.344, "mi"), "miles": (1609.344, "mi"),
                "ft": (0.3048, "ft"), "foot": (0.3048, "ft"), "feet": (0.3048, "ft"),
                "in": (0.0254, "in"), "inch": (0.0254, "in"), "inches": (0.0254, "in"),
                "yd": (0.9144, "yd"), "yard": (0.9144, "yd"), "yards": (0.9144, "yd")
            ],
            // Mass (base: grams)
            [
                "g": (1, "g"), "gram": (1, "g"), "grams": (1, "g"),
                "kg": (1000, "kg"), "mg": (0.001, "mg"),
                "lb": (453.59237, "lb"), "lbs": (453.59237, "lb"), "pound": (453.59237, "lb"), "pounds": (453.59237, "lb"),
                "oz": (28.349523125, "oz")
            ],
            // Volume (base: milliliters)
            [
                "ml": (1, "mL"), "l": (1000, "L"), "liter": (1000, "L"), "liters": (1000, "L"),
                "gal": (3785.411784, "gal"), "gallon": (3785.411784, "gal"),
                "qt": (946.352946, "qt"), "cup": (236.5882365, "cups"), "cups": (236.5882365, "cups"),
                "floz": (29.5735295625, "fl oz")
            ],
            // Data (base: bytes, decimal 1024 binary-friendly)
            [
                "b": (1, "B"), "kb": (1024, "KB"), "mb": (1_048_576, "MB"),
                "gb": (1_073_741_824, "GB"), "tb": (1_099_511_627_776, "TB")
            ]
        ]

        for family in families {
            if let from = family[fromUnit], let to = family[toUnit] {
                let converted = (value * from.factorToBase) / to.factorToBase
                let text = "\(formatNumber(converted)) \(to.label)"
                return InlineUtilityResult(
                    title: text,
                    subtitle: "\(formatNumber(value)) \(from.label) → \(to.label)",
                    insertText: text,
                    systemImage: "arrow.left.arrow.right"
                )
            }
        }

        return nil
    }

    private static func convertTemperature(value: Double, from: String, to: String) -> (value: Double, symbol: String)? {
        let norm: (String) -> String? = { u in
            switch u {
            case "c", "celsius": "c"
            case "f", "fahrenheit": "f"
            case "k", "kelvin": "k"
            default: nil
            }
        }
        guard let f = norm(from), let t = norm(to), f != t else { return nil }

        let celsius: Double = switch f {
        case "c": value
        case "f": (value - 32) * 5 / 9
        case "k": value - 273.15
        default: value
        }

        switch t {
        case "c": return (celsius, "°C")
        case "f": return (celsius * 9 / 5 + 32, "°F")
        case "k": return (celsius + 273.15, " K")
        default: return nil
        }
    }

    // MARK: - Math Calculator (Safe Recursive-Descent Parser)

    private static func evaluateMath(_ raw: String) -> InlineUtilityResult? {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: "18% of 240"
        if let pctMatch = matchPercentOf(lower) {
            let result = (pctMatch.percent / 100.0) * pctMatch.total
            let formatted = formatNumber(result)
            return InlineUtilityResult(
                title: formatted,
                subtitle: "\(formatNumber(pctMatch.percent))% of \(formatNumber(pctMatch.total))",
                insertText: formatted,
                systemImage: "percent"
            )
        }

        // Only treat as math if it contains at least one operator or function call (avoid matching plain numbers like "42")
        let hasOperator = lower.contains(where: { "+-*/^()".contains($0) })
            || lower.hasPrefix("sqrt(")
        guard hasOperator else { return nil }

        // Normalize visual symbols and constants
        let normalized = lower
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "pi", with: String(Double.pi))

        var parser = MathParser(normalized)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else {
            return nil
        }
        let formatted = formatNumber(value)
        return InlineUtilityResult(
            title: formatted,
            subtitle: "= \(raw)",
            insertText: formatted,
            systemImage: "equal.circle"
        )
    }

    private static func matchPercentOf(_ text: String) -> (percent: Double, total: Double)? {
        let pattern = #"^([+-]?\d+(?:\.\d+)?)\s*%\s+of\s+([+-]?\d+(?:\.\d+)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text),
              let p = Double(text[r1]),
              let t = Double(text[r2]) else {
            return nil
        }
        return (p, t)
    }

    public static func formatNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 1e-9, abs(value) < 1e15 {
            return String(Int64(value.rounded()))
        }
        let formatted = String(format: "%.6f", value)
        var trimmed = formatted
        while trimmed.contains(".") && (trimmed.hasSuffix("0") || trimmed.hasSuffix(".")) {
            trimmed.removeLast()
        }
        return trimmed
    }
}

private struct MathParser {
    private let chars: [Character]
    private var index: Int = 0

    init(_ input: String) {
        self.chars = Array(input)
    }

    var isAtEnd: Bool {
        var i = index
        while i < chars.count && chars[i].isWhitespace {
            i += 1
        }
        return i >= chars.count
    }

    mutating func parseExpression() -> Double? {
        guard var left = parseTerm() else { return nil }
        while true {
            skipWhitespace()
            guard index < chars.count else { break }
            let op = chars[index]
            if op == "+" || op == "-" {
                index += 1
                guard let right = parseTerm() else { return nil }
                left = (op == "+") ? (left + right) : (left - right)
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseTerm() -> Double? {
        guard var left = parsePower() else { return nil }
        while true {
            skipWhitespace()
            guard index < chars.count else { break }
            let op = chars[index]
            if op == "*" || op == "/" {
                index += 1
                guard let right = parsePower() else { return nil }
                if op == "/" {
                    guard right != 0 else { return nil }
                    left /= right
                } else {
                    left *= right
                }
            } else {
                break
            }
        }
        return left
    }

    private mutating func parsePower() -> Double? {
        guard let base = parseUnary() else { return nil }
        skipWhitespace()
        if index < chars.count, chars[index] == "^" {
            index += 1
            guard let exp = parsePower() else { return nil }
            return pow(base, exp)
        }
        return base
    }

    private mutating func parseUnary() -> Double? {
        skipWhitespace()
        guard index < chars.count else { return nil }
        if chars[index] == "+" {
            index += 1
            return parseUnary()
        }
        if chars[index] == "-" {
            index += 1
            guard let value = parseUnary() else { return nil }
            return -value
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()
        guard index < chars.count else { return nil }

        // sqrt(...)
        if remainingStartsWith("sqrt") {
            index += 4
            skipWhitespace()
            guard index < chars.count, chars[index] == "(" else { return nil }
            index += 1
            guard let inner = parseExpression(), inner >= 0 else { return nil }
            skipWhitespace()
            guard index < chars.count, chars[index] == ")" else { return nil }
            index += 1
            return sqrt(inner)
        }

        if chars[index] == "(" {
            index += 1
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            guard index < chars.count, chars[index] == ")" else { return nil }
            index += 1
            return consumeOptionalPercent(value)
        }

        let start = index
        var sawDot = false
        while index < chars.count {
            let c = chars[index]
            if c.isNumber {
                index += 1
            } else if c == "." && !sawDot {
                sawDot = true
                index += 1
            } else {
                break
            }
        }
        guard index > start else { return nil }
        let slice = String(chars[start..<index])
        guard let number = Double(slice) else { return nil }
        return consumeOptionalPercent(number)
    }

    private mutating func consumeOptionalPercent(_ value: Double) -> Double {
        skipWhitespace()
        if index < chars.count, chars[index] == "%" {
            index += 1
            return value / 100.0
        }
        return value
    }

    private mutating func skipWhitespace() {
        while index < chars.count && chars[index].isWhitespace {
            index += 1
        }
    }

    private func remainingStartsWith(_ prefix: String) -> Bool {
        let p = Array(prefix)
        guard index + p.count <= chars.count else { return false }
        for offset in 0..<p.count {
            if chars[index + offset] != p[offset] { return false }
        }
        return true
    }
}
