import AppKit

/// Lightweight shell syntax highlighter using NSAttributedString.
/// Highlights keywords, strings, comments, variables, operators, and dangerous patterns.
struct ShellSyntaxHighlighter {

    // MARK: - Theme colors

    static let backgroundColor = NSColor(calibratedRed: 0x1e/255.0, green: 0x1e/255.0, blue: 0x1e/255.0, alpha: 1.0)
    static let defaultTextColor = NSColor(calibratedRed: 0xd4/255.0, green: 0xd4/255.0, blue: 0xd4/255.0, alpha: 1.0)
    static let keywordColor = NSColor(calibratedRed: 0x56/255.0, green: 0x9c/255.0, blue: 0xd6/255.0, alpha: 1.0)
    static let stringColor = NSColor(calibratedRed: 0xce/255.0, green: 0x91/255.0, blue: 0x78/255.0, alpha: 1.0)
    static let commentColor = NSColor(calibratedRed: 0x6a/255.0, green: 0x99/255.0, blue: 0x55/255.0, alpha: 1.0)
    static let variableColor = NSColor(calibratedRed: 0x9c/255.0, green: 0xdc/255.0, blue: 0xfe/255.0, alpha: 1.0)
    static let numberColor = NSColor(calibratedRed: 0xb5/255.0, green: 0xce/255.0, blue: 0xa8/255.0, alpha: 1.0)
    static let operatorColor = NSColor(calibratedRed: 0xd4/255.0, green: 0xd4/255.0, blue: 0xd4/255.0, alpha: 1.0)
    static let flagColor = NSColor(calibratedRed: 0xce/255.0, green: 0x91/255.0, blue: 0x78/255.0, alpha: 1.0)
    static let dangerousColor = NSColor.systemRed
    static let dangerousBackgroundColor = NSColor(calibratedRed: 0.4, green: 0.0, blue: 0.0, alpha: 0.3)

    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // Shell keywords
    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
        "case", "esac", "in", "function", "return", "exit", "local", "export",
        "source", "eval", "exec", "set", "unset", "shift", "trap",
        "break", "continue", "select", "until", "declare", "typeset", "readonly",
    ]

    // Dangerous commands/patterns that should be visually emphasized
    private static let dangerousPatterns: [String] = [
        "rm\\b", "sudo\\b", "chmod\\b", "chown\\b", "mkfs\\b", "dd\\b",
        "--force\\b", "--hard\\b", "-rf\\b", "-fr\\b", "--no-verify\\b",
        "force.push", "> */dev/", "shutdown\\b", "reboot\\b", "kill\\b",
        "pkill\\b", "killall\\b", ":(){ ", "fork.bomb",
        "DROP\\b", "DELETE\\b", "TRUNCATE\\b", "curl.*\\|.*sh",
        "wget.*\\|.*sh", "eval\\b", "exec\\b",
    ]

    /// Highlight the given shell command text and return an attributed string.
    static func highlight(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: codeFont,
            .foregroundColor: defaultTextColor,
        ])

        let fullRange = NSRange(location: 0, length: result.length)
        let nsText = text as NSString

        // 1. Comments (# to end of line, but not inside strings or #!)
        applyPattern(#"(?m)(?<![\\\"'$])#(?!!).*$"#, color: commentColor, to: result, in: nsText)

        // 2. Strings — double-quoted
        applyPattern(#""(?:[^"\\]|\\.)*""#, color: stringColor, to: result, in: nsText)

        // 3. Strings — single-quoted
        applyPattern(#"'[^']*'"#, color: stringColor, to: result, in: nsText)

        // 4. Variables: $VAR, ${VAR}, $1, etc.
        applyPattern(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, color: variableColor, to: result, in: nsText)
        applyPattern(#"\$[0-9@#?!*]"#, color: variableColor, to: result, in: nsText)

        // 5. Numbers (standalone)
        applyPattern(#"(?<=\s|^)\d+(?=\s|$|[;|&>])"#, color: numberColor, to: result, in: nsText)

        // 6. Flags (--flag, -f)
        applyPattern(#"(?<=\s)-{1,2}[A-Za-z][A-Za-z0-9_-]*"#, color: flagColor, to: result, in: nsText)

        // 7. Shell keywords (word-bounded, at start of line or after ; | && ||)
        for keyword in keywords {
            applyPattern("(?<=^|[;|&\\s])\(keyword)(?=\\s|$|;)", color: keywordColor, to: result, in: nsText)
        }

        // 8. Pipe and redirection operators
        applyPattern(#"[|&]{1,2}|[<>]{1,2}|;|&&|\|\|"#, color: operatorColor, to: result, in: nsText)

        // 9. Dangerous patterns — apply red text + subtle red background
        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    result.addAttribute(.foregroundColor, value: dangerousColor, range: match.range)
                    result.addAttribute(.backgroundColor, value: dangerousBackgroundColor, range: match.range)
                }
            }
        }

        return result
    }

    private static func applyPattern(_ pattern: String, color: NSColor, to attrString: NSMutableAttributedString, in nsText: NSString) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: nsText as String, options: [], range: fullRange)
        for match in matches {
            attrString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
