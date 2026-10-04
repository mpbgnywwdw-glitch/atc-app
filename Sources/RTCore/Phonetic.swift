import Foundation

/// Converts values into the spoken form used in UK RT (CAP 413).
public enum Phonetic {
    public static let letters: [Character: String] = [
        "A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot",
        "G": "Golf", "H": "Hotel", "I": "India", "J": "Juliet", "K": "Kilo", "L": "Lima",
        "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa", "Q": "Quebec", "R": "Romeo",
        "S": "Sierra", "T": "Tango", "U": "Uniform", "V": "Victor", "W": "Whisky", "X": "X-ray",
        "Y": "Yankee", "Z": "Zulu",
    ]

    public static let digitWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]

    /// Spells a string character by character: letters phonetically, digits individually,
    /// "." as "decimal". Other characters are dropped.
    /// `spell("A1")` → "Alpha one", `spell("1013")` → "one zero one three".
    public static func spell(_ s: String) -> String {
        s.compactMap { ch -> String? in
            if let d = ch.wholeNumberValue, ch.isASCII { return digitWords[d] }
            if ch == "." { return "decimal" }
            if ch.isLetter { return letters[Character(ch.uppercased())] }
            return nil
        }.joined(separator: " ")
    }

    /// Digits spoken individually: 1013 → "one zero one three".
    public static func digits(_ value: Int) -> String { spell(String(value)) }

    /// Altitudes/heights: 2500 → "two thousand five hundred", 10000 → "one zero thousand".
    public static func altitude(_ feet: Int) -> String {
        let thousands = feet / 1000
        let hundreds = (feet % 1000) / 100
        var parts: [String] = []
        if thousands > 0 {
            parts.append((thousands >= 10 ? digits(thousands) : digitWords[thousands]) + " thousand")
        }
        if hundreds > 0 { parts.append(digitWords[hundreds] + " hundred") }
        return parts.isEmpty ? "zero" : parts.joined(separator: " ")
    }

    /// Transponder codes: digits individually, except whole thousands (7000 → "seven thousand").
    public static func squawk(_ code: String) -> String {
        if code.count == 4, code.hasSuffix("000"), let first = code.first?.wholeNumberValue {
            return digitWords[first] + " thousand"
        }
        return spell(code)
    }

    /// Frequencies: "124.750" → "one two four decimal seven five zero".
    /// Two trailing zeros are omitted ("121.500" → "one two one decimal five").
    public static func frequency(_ f: String) -> String {
        var s = f
        if s.contains("."), s.hasSuffix("00") { s.removeLast(2) }
        return spell(s)
    }

    /// Runway designators: "26" → "two six", "08L" → "zero eight left".
    public static func runway(_ r: String) -> String {
        let number = r.filter(\.isNumber)
        var spoken = spell(number)
        switch r.last {
        case "L": spoken += " left"
        case "R": spoken += " right"
        case "C": spoken += " centre"
        default: break
        }
        return spoken
    }

    /// Wind: (240, 12) → "two four zero degrees, one two knots".
    public static func wind(direction: Int, speed: Int) -> String {
        spell(String(format: "%03d", direction)) + " degrees, " + spell(String(speed)) + " knots"
    }

    /// Headings: 360 → "three six zero".
    public static func heading(_ h: Int) -> String { spell(String(format: "%03d", h)) }
}
