import SwiftUI

/// Card text with light formula support: anything between $…$ is shown as maths, with LaTeX-style
/// shorthand turned into symbols (\alpha → α, x^2 → x², H_2O → H₂O, \frac{a}{b} → a⁄b, \sqrt{x} → √x).
/// It covers what fits on a flashcard, not full LaTeX layout.
struct MathText: View {
    var text: String
    var font: Font = .title3

    var body: some View {
        Text(MathText.attributed(text)).font(font)
    }

    static func attributed(_ s: String) -> AttributedString {
        var out = AttributedString()
        var inMath = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(inMath ? convert(buffer) : buffer)
            if inMath {
                piece.font = .system(.title3, design: .serif).italic()
                piece.foregroundColor = Color(hex: "#C9D4FF")
            }
            out += piece
            buffer = ""
        }
        var chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count && chars[i + 1] == "$" { buffer.append("$"); i += 2; continue }
            if chars[i] == "$" {
                flush()
                inMath.toggle()
                // $$ … $$ is treated the same as $ … $
                if i + 1 < chars.count && chars[i + 1] == "$" { i += 1 }
            } else {
                buffer.append(chars[i])
            }
            i += 1
        }
        if inMath { buffer = "$" + buffer; inMath = false }
        flush()
        chars.removeAll()
        return out
    }

    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "times": "×", "div": "÷", "cdot": "·", "pm": "±", "mp": "∓", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "propto": "∝", "infty": "∞", "partial": "∂", "nabla": "∇", "int": "∫", "oint": "∮", "iint": "∬",
        "sum": "Σ", "prod": "Π", "rightarrow": "→", "to": "→", "leftarrow": "←", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "leftrightarrow": "↔", "Leftrightarrow": "⇔", "rightleftharpoons": "⇌", "in": "∈", "notin": "∉", "subset": "⊂",
        "subseteq": "⊆", "cup": "∪", "cap": "∩", "emptyset": "∅", "forall": "∀", "exists": "∃", "neg": "¬", "land": "∧",
        "lor": "∨", "degree": "°", "circ": "°", "angle": "∠", "perp": "⊥", "parallel": "∥", "hbar": "ℏ", "ell": "ℓ",
        "therefore": "∴", "because": "∵", "ldots": "…", "cdots": "⋯", "prime": "′", "deg": "°", "sqrt": "√",
        "Re": "ℜ", "Im": "ℑ", "mathbb{R}": "ℝ", "mathbb{N}": "ℕ", "mathbb{Z}": "ℤ", "mathbb{Q}": "ℚ", "mathbb{C}": "ℂ",
        "quad": "  ", "qquad": "    ", ",": " ", ";": " ", "!": "", "left": "", "right": "",
    ]
    private static let sup: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻",
        "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "k": "ᵏ", "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "T": "ᵀ",
    ]
    private static let sub: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋",
        "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "i": "ᵢ", "j": "ⱼ", "n": "ₙ", "m": "ₘ", "k": "ₖ",
        "p": "ₚ", "s": "ₛ", "t": "ₜ", "r": "ᵣ", "u": "ᵤ", "v": "ᵥ", "h": "ₕ", "l": "ₗ",
    ]

    /// LaTeX shorthand → Unicode.
    static func convert(_ input: String) -> String {
        var s = input
        // \frac{a}{b} → (a)/(b), simplified when each side is a single token.
        while let r = s.range(of: #"\\frac\{([^{}]*)\}\{([^{}]*)\}"#, options: .regularExpression) {
            let inner = String(s[r])
            let parts = inner.dropFirst(6).dropLast().components(separatedBy: "}{")
            let a = parts.first ?? "", b = parts.count > 1 ? parts[1] : ""
            let wrap: (String) -> String = { $0.count > 1 && $0.contains(where: { "+-".contains($0) }) ? "(\($0))" : $0 }
            s.replaceSubrange(r, with: "\(wrap(a))⁄\(wrap(b))")
        }
        while let r = s.range(of: #"\\sqrt\{([^{}]*)\}"#, options: .regularExpression) {
            let inner = String(s[r].dropFirst(6).dropLast())
            s.replaceSubrange(r, with: inner.count > 1 ? "√(\(inner))" : "√\(inner)")
        }
        while let r = s.range(of: #"\\(text|mathrm|mathbf|mathit|operatorname)\{([^{}]*)\}"#, options: .regularExpression) {
            let raw = String(s[r])
            let inner = raw.drop(while: { $0 != "{" }).dropFirst().dropLast()
            s.replaceSubrange(r, with: String(inner))
        }
        // Named symbols, longest first so \leftarrow beats \left.
        for (name, sym) in symbols.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: "\\" + name, with: sym)
        }
        s = script(s, marker: "^", map: sup)
        s = script(s, marker: "_", map: sub)
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        s = s.replacingOccurrences(of: "*", with: "·").replacingOccurrences(of: "<=", with: "≤").replacingOccurrences(of: ">=", with: "≥")
            .replacingOccurrences(of: "!=", with: "≠").replacingOccurrences(of: "->", with: "→")
        return s
    }

    /// x^2, x^{10}, H_2, a_{n+1}. Characters with no small form keep a ^ or _ in front.
    private static func script(_ s: String, marker: Character, map: [Character: Character]) -> String {
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == marker, i + 1 < chars.count else { out.append(c); i += 1; continue }
            var group: [Character] = []
            if chars[i + 1] == "{" {
                var j = i + 2
                while j < chars.count && chars[j] != "}" { group.append(chars[j]); j += 1 }
                i = j + 1
            } else {
                group = [chars[i + 1]]
                i += 2
            }
            if group.allSatisfy({ map[$0] != nil }) {
                out += String(group.compactMap { map[$0] })
            } else {
                out += String(marker) + (group.count > 1 ? "(" + String(group) + ")" : String(group))
            }
        }
        return out
    }
}
