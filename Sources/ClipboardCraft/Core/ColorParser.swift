import AppKit
import SwiftUI

struct ParsedColor: Hashable {
    var r: Double, g: Double, b: Double, a: Double

    var hex: String {
        let base = String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        return a < 0.999 ? base + String(format: "%02X", Int(round(a * 255))) : base
    }

    var rgbString: String {
        let (R, G, B) = (Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        return a < 0.999 ? "rgba(\(R), \(G), \(B), \(Self.trim(a)))" : "rgb(\(R), \(G), \(B))"
    }

    var hslString: String {
        let (h, s, l) = hsl
        let base = "\(Int(round(h))), \(Int(round(s * 100)))%, \(Int(round(l * 100)))%"
        return a < 0.999 ? "hsla(\(base), \(Self.trim(a)))" : "hsl(\(base))"
    }

    var swiftUIString: String {
        "Color(red: \(Self.trim(r)), green: \(Self.trim(g)), blue: \(Self.trim(b))\(a < 0.999 ? ", opacity: \(Self.trim(a))" : ""))"
    }

    var hsl: (Double, Double, Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        switch maxV {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Relative luminance, used to pick legible text on top of the swatch.
    var isLight: Bool { (0.2126 * r + 0.7152 * g + 0.0722 * b) * a + (1 - a) > 0.6 }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.3f", v)
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }
}

enum ColorParser {
    static func parse(_ raw: String) -> ParsedColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.count <= 64, !s.contains("\n") else { return nil }
        if s.hasPrefix("#") { return parseHex(String(s.dropFirst())) }
        if s.hasPrefix("0x"), s.count == 8 { return parseHex(String(s.dropFirst(2))) }
        if s.hasPrefix("rgb") { return parseFunctional(s, hsl: false) }
        if s.hasPrefix("hsl") { return parseFunctional(s, hsl: true) }
        return nil
    }

    private static func parseHex(_ h: String) -> ParsedColor? {
        guard h.allSatisfy(\.isHexDigit), [3, 4, 6, 8].contains(h.count) else { return nil }
        var chars = Array(h)
        if chars.count <= 4 { chars = chars.flatMap { [$0, $0] } }
        func byte(_ i: Int) -> Double { Double(Int(String(chars[i...i + 1]), radix: 16) ?? 0) / 255 }
        return ParsedColor(r: byte(0), g: byte(2), b: byte(4), a: chars.count == 8 ? byte(6) : 1)
    }

    private static func parseFunctional(_ s: String, hsl: Bool) -> ParsedColor? {
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let name = s[..<open]
        guard ["rgb", "rgba", "hsl", "hsla"].contains(String(name)) else { return nil }
        let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
        let parts = inner.replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func value(_ p: String, scale: Double) -> Double? {
            if p.hasSuffix("%") { return Double(p.dropLast()).map { $0 / 100 } }
            if p.hasSuffix("deg") { return Double(p.dropLast(3)).map { $0 / scale } }
            return Double(p).map { $0 / scale }
        }
        let alpha = parts.count == 4 ? (value(parts[3], scale: 1) ?? 1) : 1
        if hsl {
            guard let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                  let sat = value(parts[1], scale: 100), let l = value(parts[2], scale: 100) else { return nil }
            let (r, g, b) = hslToRGB(h: h, s: sat, l: l)
            return ParsedColor(r: r, g: g, b: b, a: min(max(alpha, 0), 1))
        }
        guard let r = value(parts[0], scale: 255), let g = value(parts[1], scale: 255), let b = value(parts[2], scale: 255),
              [r, g, b].allSatisfy({ (0...1).contains($0) }) else { return nil }
        return ParsedColor(r: r, g: g, b: b, a: min(max(alpha, 0), 1))
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var (r, g, b): (Double, Double, Double)
        switch hp {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        return (r + m, g + m, b + m)
    }
}
