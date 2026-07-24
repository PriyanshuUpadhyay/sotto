import Foundation

/// Compact Double Metaphone (Lawrence Philips' algorithm). Returns the two
/// phonetic keys for a word; `alternate == primary` when no branch is taken.
/// Pure, deterministic, ASCII-folded + uppercased + letters-only input.
/// Output is capped at 4 characters per key (standard behaviour).
enum DoubleMetaphone {
    static func encode(_ s: String) -> (primary: String, alternate: String) {
        let folded = s.folding(options: .diacriticInsensitive, locale: nil).uppercased()
        let chars: [Character] = folded.filter { $0 >= "A" && $0 <= "Z" }
        let length = chars.count
        guard length > 0 else { return ("", "") }
        let last = length - 1

        var primary = ""
        var secondary = ""
        var current = 0

        let wordStr = String(chars)
        let isSlavoGermanic = wordStr.contains("W") || wordStr.contains("K")
            || wordStr.contains("CZ") || wordStr.contains("WITZ")

        func charAt(_ i: Int) -> Character { (i >= 0 && i < length) ? chars[i] : " " }
        func isVowel(_ i: Int) -> Bool {
            guard i >= 0 && i < length else { return false }
            return "AEIOUY".contains(chars[i])
        }
        func stringAt(_ start: Int, _ len: Int, _ options: [String]) -> Bool {
            guard start >= 0, start + len <= length else { return false }
            return options.contains(String(chars[start..<start + len]))
        }
        func add(_ p: String, _ s: String? = nil) {
            primary += p
            secondary += (s ?? p)
        }

        // Skip silent initial letters.
        if stringAt(0, 2, ["GN", "KN", "PN", "WR", "PS"]) { current = 1 }
        // Initial X (e.g. "Xavier") → S.
        if charAt(0) == "X" { add("S"); current = 1 }

        while primary.count < 4 || secondary.count < 4 {
            if current >= length { break }
            let c = charAt(current)
            switch c {
            case "A", "E", "I", "O", "U", "Y":
                if current == 0 { add("A") }
                current += 1

            case "B":
                add("P")
                current += (charAt(current + 1) == "B") ? 2 : 1

            case "C":
                // Various Germanic.
                if current > 1 && !isVowel(current - 2) && stringAt(current - 1, 3, ["ACH"])
                    && charAt(current + 2) != "I"
                    && (charAt(current + 2) != "E" || stringAt(current - 2, 6, ["BACHER", "MACHER"])) {
                    add("K"); current += 2; break
                }
                if current == 0 && stringAt(current, 6, ["CAESAR"]) { add("S"); current += 2; break }
                if stringAt(current, 4, ["CHIA"]) { add("K"); current += 2; break }
                if stringAt(current, 2, ["CH"]) {
                    if current > 0 && stringAt(current, 4, ["CHAE"]) { add("K", "X"); current += 2; break }
                    if current == 0
                        && (stringAt(current + 1, 5, ["HARAC", "HARIS"])
                            || stringAt(current + 1, 3, ["HOR", "HYM", "HIA", "HEM"]))
                        && !stringAt(0, 5, ["CHORE"]) {
                        add("K"); current += 2; break
                    }
                    if stringAt(0, 4, ["VAN ", "VON "]) || stringAt(0, 3, ["SCH"])
                        || stringAt(current - 2, 6, ["ORCHES", "ARCHIT", "ORCHID"])
                        || stringAt(current + 2, 1, ["T", "S"])
                        || ((stringAt(current - 1, 1, ["A", "O", "U", "E"]) || current == 0)
                            && stringAt(current + 2, 1, ["L", "R", "N", "M", "B", "H", "F", "V", "W", " "])) {
                        add("K")
                    } else if current > 0 {
                        if stringAt(0, 2, ["MC"]) { add("K") } else { add("X", "K") }
                    } else {
                        add("X")
                    }
                    current += 2; break
                }
                if stringAt(current, 2, ["CZ"]) && !stringAt(current - 2, 4, ["WICZ"]) {
                    add("S", "X"); current += 2; break
                }
                if stringAt(current + 1, 3, ["CIA"]) { add("X"); current += 3; break }
                if stringAt(current, 2, ["CC"]) && !(current == 1 && charAt(0) == "M") {
                    if stringAt(current + 2, 1, ["I", "E", "H"]) && !stringAt(current + 2, 2, ["HU"]) {
                        if (current == 1 && charAt(current - 1) == "A")
                            || stringAt(current - 1, 5, ["UCCEE", "UCCES"]) {
                            add("KS")
                        } else {
                            add("X")
                        }
                        current += 3; break
                    } else {
                        add("K"); current += 2; break
                    }
                }
                if stringAt(current, 2, ["CK", "CG", "CQ"]) { add("K"); current += 2; break }
                if stringAt(current, 2, ["CI", "CE", "CY"]) {
                    if stringAt(current, 3, ["CIO", "CIE", "CIA"]) { add("S", "X") } else { add("S") }
                    current += 2; break
                }
                add("K")
                if stringAt(current + 1, 2, [" C", " Q", " G"]) {
                    current += 3
                } else if stringAt(current + 1, 1, ["C", "K", "Q"]) && !stringAt(current + 1, 2, ["CE", "CI"]) {
                    current += 2
                } else {
                    current += 1
                }

            case "D":
                if stringAt(current, 2, ["DG"]) {
                    if stringAt(current + 2, 1, ["I", "E", "Y"]) { add("J"); current += 3 }
                    else { add("TK"); current += 2 }
                    break
                }
                if stringAt(current, 2, ["DT", "DD"]) { add("T"); current += 2; break }
                add("T"); current += 1

            case "F":
                add("F"); current += (charAt(current + 1) == "F") ? 2 : 1

            case "G":
                if charAt(current + 1) == "H" {
                    if current > 0 && !isVowel(current - 1) { add("K"); current += 2; break }
                    if current == 0 {
                        if charAt(current + 2) == "I" { add("J") } else { add("K") }
                        current += 2; break
                    }
                    if (current > 1 && stringAt(current - 2, 1, ["B", "H", "D"]))
                        || (current > 2 && stringAt(current - 3, 1, ["B", "H", "D"]))
                        || (current > 3 && stringAt(current - 4, 1, ["B", "H"])) {
                        current += 2; break
                    }
                    if current > 2 && charAt(current - 1) == "U"
                        && stringAt(current - 3, 1, ["C", "G", "L", "R", "T"]) {
                        add("F")
                    } else if current > 0 && charAt(current - 1) != "I" {
                        add("K")
                    }
                    current += 2; break
                }
                if charAt(current + 1) == "N" {
                    if current == 1 && isVowel(0) && !isSlavoGermanic { add("KN", "N") }
                    else if !stringAt(current + 2, 2, ["EY"]) && charAt(current + 1) != "Y" && !isSlavoGermanic {
                        add("N", "KN")
                    } else { add("KN") }
                    current += 2; break
                }
                if stringAt(current + 1, 2, ["LI"]) && !isSlavoGermanic { add("KL", "L"); current += 2; break }
                if current == 0
                    && (charAt(current + 1) == "Y"
                        || stringAt(current + 1, 2, ["ES", "EP", "EB", "EL", "EY", "IB", "IL", "IN", "IE", "EI", "ER"])) {
                    add("K", "J"); current += 2; break
                }
                if (stringAt(current + 1, 2, ["ER"]) || charAt(current + 1) == "Y")
                    && !stringAt(0, 6, ["DANGER", "RANGER", "MANGER"])
                    && !stringAt(current - 1, 1, ["E", "I"])
                    && !stringAt(current - 1, 3, ["RGY", "OGY"]) {
                    add("K", "J"); current += 2; break
                }
                if stringAt(current + 1, 1, ["E", "I", "Y"]) || stringAt(current - 1, 4, ["AGGI", "OGGI"]) {
                    if stringAt(0, 4, ["VAN ", "VON "]) || stringAt(0, 3, ["SCH"]) || stringAt(current + 1, 2, ["ET"]) {
                        add("K")
                    } else if stringAt(current + 1, 4, ["IER "]) {
                        add("J")
                    } else {
                        add("J", "K")
                    }
                    current += 2; break
                }
                add("K")
                current += (charAt(current + 1) == "G") ? 2 : 1

            case "H":
                if (current == 0 || isVowel(current - 1)) && isVowel(current + 1) { add("H"); current += 2 }
                else { current += 1 }

            case "J":
                if stringAt(current, 4, ["JOSE"]) || stringAt(0, 4, ["SAN "]) {
                    if (current == 0 && charAt(current + 4) == " ") || stringAt(0, 4, ["SAN "]) { add("H") }
                    else { add("J", "H") }
                    current += 1; break
                }
                if current == 0 && !stringAt(current, 4, ["JOSE"]) {
                    add("J", "A")
                } else if isVowel(current - 1) && !isSlavoGermanic
                    && (charAt(current + 1) == "A" || charAt(current + 1) == "O") {
                    add("J", "H")
                } else if current == last {
                    add("J", "")
                } else if !stringAt(current + 1, 1, ["L", "T", "K", "S", "N", "M", "B", "Z"])
                    && !stringAt(current - 1, 1, ["S", "K", "L"]) {
                    add("J")
                }
                current += (charAt(current + 1) == "J") ? 2 : 1

            case "K":
                add("K"); current += (charAt(current + 1) == "K") ? 2 : 1

            case "L":
                if charAt(current + 1) == "L" {
                    if (current == length - 3 && stringAt(current - 1, 4, ["ILLO", "ILLA", "ALLE"]))
                        || ((stringAt(last - 1, 2, ["AS", "OS"]) || stringAt(last, 1, ["A", "O"]))
                            && stringAt(current - 1, 4, ["ALLE"])) {
                        add("L", ""); current += 2; break
                    }
                    current += 2
                } else {
                    current += 1
                }
                add("L")

            case "M":
                if (stringAt(current - 1, 3, ["UMB"]) && (current + 1 == last || stringAt(current + 2, 2, ["ER"])))
                    || charAt(current + 1) == "M" {
                    current += 2
                } else {
                    current += 1
                }
                add("M")

            case "N":
                add("N"); current += (charAt(current + 1) == "N") ? 2 : 1

            case "P":
                if charAt(current + 1) == "H" { add("F"); current += 2; break }
                add("P"); current += stringAt(current + 1, 1, ["P", "B"]) ? 2 : 1

            case "Q":
                add("K"); current += (charAt(current + 1) == "Q") ? 2 : 1

            case "R":
                if current == last && !isSlavoGermanic && stringAt(current - 2, 2, ["IE"])
                    && !stringAt(current - 4, 2, ["ME", "MA"]) {
                    add("", "R")
                } else {
                    add("R")
                }
                current += (charAt(current + 1) == "R") ? 2 : 1

            case "S":
                if stringAt(current - 1, 3, ["ISL", "YSL"]) { current += 1; break }
                if current == 0 && stringAt(current, 5, ["SUGAR"]) { add("X", "S"); current += 1; break }
                if stringAt(current, 2, ["SH"]) {
                    if stringAt(current + 1, 4, ["HEIM", "HOEK", "HOLM", "HOLZ"]) { add("S") } else { add("X") }
                    current += 2; break
                }
                if stringAt(current, 3, ["SIO", "SIA"]) || stringAt(current, 4, ["SIAN"]) {
                    if !isSlavoGermanic { add("S", "X") } else { add("S") }
                    current += 3; break
                }
                if (current == 0 && stringAt(current + 1, 1, ["M", "N", "L", "W"])) || stringAt(current + 1, 1, ["Z"]) {
                    add("S", "X")
                    current += (charAt(current + 1) == "Z") ? 2 : 1
                    break
                }
                if stringAt(current, 2, ["SC"]) {
                    if charAt(current + 2) == "H" {
                        if stringAt(current + 3, 2, ["OO", "ER", "EN", "UY", "ED", "EM"]) {
                            if stringAt(current + 3, 2, ["ER", "EN"]) { add("X", "SK") } else { add("SK") }
                        } else if current == 0 && !isVowel(3) && charAt(3) != "W" {
                            add("X", "S")
                        } else {
                            add("X")
                        }
                    } else if stringAt(current + 2, 1, ["I", "E", "Y"]) {
                        add("S")
                    } else {
                        add("SK")
                    }
                    current += 3; break
                }
                if current == last && stringAt(current - 2, 2, ["AI", "OI"]) { add("", "S") } else { add("S") }
                current += stringAt(current + 1, 1, ["S", "Z"]) ? 2 : 1

            case "T":
                if stringAt(current, 4, ["TION"]) { add("X"); current += 3; break }
                if stringAt(current, 3, ["TIA", "TCH"]) { add("X"); current += 3; break }
                if stringAt(current, 2, ["TH"]) || stringAt(current, 3, ["TTH"]) {
                    if stringAt(current + 2, 2, ["OM", "AM"]) || stringAt(0, 4, ["VAN ", "VON "]) || stringAt(0, 3, ["SCH"]) {
                        add("T")
                    } else {
                        add("0", "T")
                    }
                    current += 2; break
                }
                add("T"); current += stringAt(current + 1, 1, ["T", "D"]) ? 2 : 1

            case "V":
                add("F"); current += (charAt(current + 1) == "V") ? 2 : 1

            case "W":
                if stringAt(current, 2, ["WR"]) { add("R"); current += 2; break }
                if current == 0 && (isVowel(current + 1) || stringAt(current, 2, ["WH"])) {
                    if isVowel(current + 1) { add("A", "F") } else { add("A") }
                    current += 1; break
                }
                if (current == last && isVowel(current - 1))
                    || stringAt(current - 1, 5, ["EWSKI", "EWSKY", "OWSKI", "OWSKY"])
                    || stringAt(0, 3, ["SCH"]) {
                    add("", "F"); current += 1; break
                }
                if stringAt(current, 4, ["WICZ", "WITZ"]) { add("TS", "FX"); current += 4; break }
                current += 1

            case "X":
                if !(current == last
                    && (stringAt(current - 3, 3, ["IAU", "EAU"]) || stringAt(current - 2, 2, ["AU", "OU"]))) {
                    add("KS")
                }
                current += stringAt(current + 1, 1, ["C", "X"]) ? 2 : 1

            case "Z":
                if charAt(current + 1) == "H" { add("J"); current += 2; break }
                if stringAt(current + 1, 2, ["ZO", "ZI", "ZA"])
                    || (isSlavoGermanic && current > 0 && charAt(current - 1) != "T") {
                    add("S", "TS")
                } else {
                    add("S")
                }
                current += (charAt(current + 1) == "Z") ? 2 : 1

            default:
                current += 1
            }
        }

        return (primary, secondary)
    }
}
