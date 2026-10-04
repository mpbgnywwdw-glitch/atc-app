import Foundation

/// Turns free text (a speech-recognition transcript or a written model answer) into a
/// canonical token stream so that differently-written versions of the same transmission compare equal:
///
/// * phonetic letters become single letters ("Golf Alpha" → "g a"), registrations are expanded ("G-ABCD" → "g a b c d")
/// * numbers are collapsed into digit strings ("one zero one three" / "1013" → "1013",
///   "two thousand five hundred" → "2500", "one two four decimal seven five zero" → "124.75")
/// * RT pronunciations and common variants are unified ("niner" → "nine", "take-off" → "takeoff", "Q N H" → "qnh")
public enum Normalizer {
    public static func canonical(_ text: String) -> String { tokens(text).joined(separator: " ") }

    public static func tokens(_ text: String) -> [String] {
        var s = text.replacingOccurrences(of: "’", with: "'")

        // Written registrations, before lowercasing so we only catch upper-case letter groups.
        s = s.replacingRegex("\\bG-?([A-Z]{4})\\b") { "g " + spaced($0[1]) }
        s = s.replacingRegex("\\bG-([A-Z]{2})\\b") { "g " + spaced($0[1]) }
        s = s.replacingRegex("\\b[Gg]olf\\s+([A-Z]{4}|[A-Z]{2})\\b") { "g " + spaced($0[1]) }

        s = s.lowercased()
        for _ in 0..<2 { s = s.replacingRegex("(\\d),(\\d{3})", template: "$1$2") }

        for (pattern, replacement) in phraseRewrites {
            s = s.replacingRegex(pattern, template: replacement)
        }

        s = s.replacingRegex("(\\d)([a-z])", template: "$1 $2")
        s = s.replacingRegex("([a-z])(\\d)", template: "$1 $2")
        // Punctuation separates phrases: keep a marker so "PA28, 10 miles" doesn't become "2810".
        s = s.replacingRegex("(?<!\\d)\\.|\\.(?!\\d)|[,;:!?]", template: " | ")
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingRegex("[^a-z0-9.| ]", template: " ")

        let words = s.split(whereSeparator: \.isWhitespace).map { word -> String in
            let w = wordMap[String(word)] ?? String(word)
            return phoneticLetters[w] ?? w
        }
        return groupNumbers(fixDigitHomophones(words))
    }

    /// Replaces digit homophones only where a number is clearly meant: after a designator or another digit,
    /// and before a digit (or at the end of the transmission).
    static func fixDigitHomophones(_ words: [String]) -> [String] {
        var out = words
        for i in words.indices {
            guard let digit = digitHomophones[words[i]] else { continue }
            let prev = i > 0 ? out[i - 1] : ""
            let next = i + 1 < words.count ? words[i + 1] : ""
            let prevIsNumber = isNumberWord(prev) || numberDesignators.contains(prev)
            let nextIsDigit = digitWords[next] != nil || isNumeral(next) || digitHomophones[next] != nil
            if prevIsNumber && (nextIsDigit || next.isEmpty || next == separator) {
                out[i] = digit
            }
        }
        return out
    }

    // MARK: - Tables

    static let phraseRewrites: [(String, String)] = [
        ("take[- ]?off", "takeoff"),
        ("\\bx[- ]ray\\b", "xray"),
        ("\\bpan[- ]?pan\\b", "pan pan"),
        ("\\bmay[- ]day\\b", "mayday"),
        ("\\bq\\.? ?n\\.? ?h\\b|\\bq and h\\b", "qnh"),
        ("\\bq\\.? ?f\\.? ?e\\b", "qfe"),
        ("\\bdead[- ]side\\b", "deadside"),
        ("\\bo'? ?clock\\b", "oclock"),
        ("\\bwil[- ]co\\b", "wilco"),
        ("\\bfree[- ]call\\b", "freecall"),
        ("\\bmat'?s\\b|\\bmattz\\b", "matz"),
        ("\\bp\\.?o\\.?b\\b", "pob"),
        // Common speech-recognition mishearings of RT words.
        ("\\bwill ?co\\b|\\bwilko\\b|\\bwilcox\\b|\\bwillco\\b", "wilco"),
        ("\\bsquak\\b|\\bsquark\\b|\\bsquawks\\b|\\bsquawking\\b|\\bsquawked\\b", "squawk"),
        ("\\b(?:queue|cue) ?(?:n|and|an) ?h\\b|\\bq ?n ?age\\b", "qnh"),
        ("\\b(?:queue|cue) ?f ?e\\b", "qfe"),
        ("\\bpam ?pam\\b|\\bpan ?am\\b", "pan pan"),
        ("\\ba firm\\b", "affirm"),
        ("\\bnine ?er\\b|\\bniner's\\b", "niner"),
        ("\\bgulf\\b", "golf"),
        ("\\bdown ?wind\\b", "downwind"),
        ("\\bline up in wait\\b|\\bline up and weight\\b", "line up and wait"),
    ]

    /// Words after which "to", "for", "oh" etc. are almost certainly misheard digits.
    static let numberDesignators: Set<String> = [
        "runway", "qnh", "qfe", "squawk", "heading", "pressure", "decimal", "point", "number", "flight", "level",
    ]

    /// Homophones of digits: "runway to six" → "runway two six", "one zero one for" → "one zero one four".
    static let digitHomophones: [String: String] = [
        "to": "two", "too": "two", "for": "four", "fore": "four", "won": "one", "oh": "zero", "ate": "eight",
    ]

    static let wordMap: [String: String] = [
        "niner": "nine", "tree": "three", "fife": "five", "fower": "four", "wun": "one", "ait": "eight",
        "alfa": "alpha", "juliett": "juliet", "whiskey": "whisky",
        "center": "centre", "ok": "okay", "okey": "okay",
    ]

    static let phoneticLetters: [String: String] = [
        "alpha": "a", "bravo": "b", "charlie": "c", "delta": "d", "echo": "e", "foxtrot": "f",
        "golf": "g", "hotel": "h", "india": "i", "juliet": "j", "kilo": "k", "lima": "l",
        "mike": "m", "november": "n", "oscar": "o", "papa": "p", "quebec": "q", "romeo": "r",
        "sierra": "s", "tango": "t", "uniform": "u", "victor": "v", "whisky": "w", "xray": "x",
        "yankee": "y", "zulu": "z",
    ]

    static let digitWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    static let teenWords: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tensWords: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    // MARK: - Numbers

    static func isNumeral(_ t: String) -> Bool {
        guard let first = t.first, first.isASCII, first.isNumber else { return false }
        return t.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
    }

    static func isNumberWord(_ t: String) -> Bool {
        digitWords[t] != nil || teenWords[t] != nil || tensWords[t] != nil
            || t == "hundred" || t == "thousand" || isNumeral(t)
    }

    static let separator = "|"

    static func groupNumbers(_ words: [String]) -> [String] {
        var out: [String] = []
        var group: [String] = []
        func flush() {
            if !group.isEmpty { out.append(convert(group)) }
            group.removeAll()
        }
        for (i, w) in words.enumerated() {
            if w == separator {
                flush()
            } else if isNumberWord(w) {
                group.append(w)
            } else if (w == "decimal" || w == "point"), !group.isEmpty, !group.contains("decimal"),
                      i + 1 < words.count, isNumberWord(words[i + 1]) {
                group.append("decimal")
            } else {
                flush()
                out.append(w)
            }
        }
        flush()
        return out
    }

    static func convert(_ group: [String]) -> String {
        if let d = group.firstIndex(of: "decimal") {
            let whole = convert(Array(group[..<d]))
            let fraction = convert(Array(group[(d + 1)...]))
            return trimDecimal(whole + "." + fraction)
        }
        if group.contains("hundred") || group.contains("thousand") {
            var total = 0, rest = 0
            var segment: [String] = []
            for t in group {
                if t == "thousand" {
                    total += (Int(plain(segment)) ?? 1) * 1000
                    segment = []
                } else if t == "hundred" {
                    rest += (Int(plain(segment)) ?? 1) * 100
                    segment = []
                } else {
                    segment.append(t)
                }
            }
            rest += Int(plain(segment)) ?? 0
            return String(total + rest)
        }
        return trimDecimal(plain(group))
    }

    /// Concatenates digits: ["two", "six"] → "26", ["twenty", "six"] → "26", ["1013"] → "1013".
    static func plain(_ group: [String]) -> String {
        var out = ""
        var i = 0
        while i < group.count {
            let t = group[i]
            if let tens = tensWords[t] {
                if i + 1 < group.count, let d = digitWords[group[i + 1]], d > 0 {
                    out += String(tens + d)
                    i += 2
                    continue
                }
                out += String(tens)
            } else if let d = digitWords[t] {
                out += String(d)
            } else if let teen = teenWords[t] {
                out += String(teen)
            } else {
                out += t
            }
            i += 1
        }
        return out
    }

    /// "124.750" → "124.75", "121.500" → "121.5", "118.000" → "118.0".
    static func trimDecimal(_ s: String) -> String {
        guard let dot = s.firstIndex(of: ".") else { return s }
        let whole = s[..<dot]
        var fraction = String(s[s.index(after: dot)...]).filter { $0 != "." }
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return String(whole) + "." + (fraction.isEmpty ? "0" : fraction)
    }

    static func spaced(_ letters: String) -> String {
        letters.lowercased().map(String.init).joined(separator: " ")
    }
}

extension String {
    func replacingRegex(_ pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: (self as NSString).length),
                                           withTemplate: template)
    }

    func replacingRegex(_ pattern: String, transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += transform(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
