//
//  TokenizerParser.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//
//  All sub-parsers are `mutating` extensions on `UnicodeScalarView`.
//  They accept an explicit `startIndex` parameter — the index saved by the
//  caller *before* the Trie consumed the opening delimiter — so that every
//  token's range correctly spans from the opening delimiter to the closing one.
//

import Foundation

// MARK: - Whitespace

extension UnicodeScalarView {

    /// Advances past all leading whitespace and newline characters.
    mutating func skipWhitespace() {
        while let s = first, CharacterSet.whitespacesAndNewlines.contains(s) {
            removeFirst()
        }
    }
}

// MARK: - String literals

extension UnicodeScalarView {

    /// Reads characters until the closing `terminator` scalar is matched.
    ///
    /// `startIndex` is the index of the opening delimiter (already consumed by
    /// the Trie match); the returned token's range spans from `startIndex` to
    /// (but not including) the closing delimiter.
    ///
    /// Returns `.invalid(.unterminatedString)` when EOF is reached before the
    /// closing delimiter is found.
    mutating func parseLiteral(startIndex: Index, until terminator: Unicode.Scalar) -> Token {
        var body = ""
        while let scalar = popFirst() {
            if scalar == terminator {
                // `self.startIndex` now points one past the closing delimiter.
                // The token body range ends just before that closing delimiter,
                // i.e. at the position we were at *before* popFirst() consumed it.
                let endIndex = index(self.startIndex, offsetBy: -1, limitedBy: self.startIndex)
                    ?? self.startIndex
                return Token(type: .literal(body), range: startIndex ..< endIndex)
            }
            body.append(Character(scalar))
        }
        // Exhausted without finding the closing delimiter.
        return Token(type: .invalid(.unterminatedString(body)), range: startIndex ..< self.startIndex)
    }
}

// MARK: - Regex literals

extension UnicodeScalarView {

    /// Reads characters until the closing `/` is matched, producing a `.regex`
    /// token whose body is everything between the two slashes.
    ///
    /// `startIndex` is the index of the opening `/` (already consumed by the
    /// Trie match).
    mutating func parseRegexDefinition(startIndex: Index, until terminator: Unicode.Scalar) -> Token {
        var body = ""
        while let scalar = popFirst() {
            if scalar == terminator {
                let endIndex = index(self.startIndex, offsetBy: -1, limitedBy: self.startIndex)
                    ?? self.startIndex
                return Token(type: .regex(body), range: startIndex ..< endIndex)
            }
            body.append(Character(scalar))
        }
        return Token(type: .invalid(.unterminatedString(body)), range: startIndex ..< self.startIndex)
    }
}

// MARK: - Line comments

extension UnicodeScalarView {

    /// Reads until a newline character is encountered (not consumed).
    ///
    /// Returns `nil` only when the comment marker is immediately followed by
    /// end-of-input (empty comment on the last line with no trailing newline).
    /// In that case a comment token with an empty body is returned rather than
    /// nil, so the token stream is never broken.
    mutating func parseLineComment(startIndex: Index) -> Token {
        let body = readCharacters(where: { !CharacterSet.newlines.contains($0) }) ?? ""
        return Token(type: .comment(body), range: startIndex ..< self.startIndex)
    }
}

// MARK: - Block comments

extension UnicodeScalarView {

    /// Reads until the two-character closing marker (`*/` or `*)`) is found.
    ///
    /// `startIndex` is the index of the opening marker's first character
    /// (already consumed by the Trie match).
    ///
    /// Returns `.invalid(.unterminatedString)` — rather than `nil` or a crash —
    /// when the input is exhausted before the closing marker is found.  This
    /// keeps the token stream intact and lets the parser report a proper error.
    mutating func parseBlockComment(startIndex: Index, match closing: String) -> Token {
        precondition(closing.unicodeScalars.count == 2)
        let close = Array(closing.unicodeScalars)
        var body  = ""

        while let scalar = popFirst() {
            if scalar == close[0], let next = popFirst() {
                if next == close[1] {
                    return Token(type: .comment(body), range: startIndex ..< self.startIndex)
                }
                // `next` was not the second closing character; keep both.
                body.append(Character(scalar))
                body.append(Character(next))
                continue
            }
            body.append(Character(scalar))
        }

        // Closing marker never found — unterminated block comment.
        return Token(type: .invalid(.unterminatedString(body)), range: startIndex ..< self.startIndex)
    }
}

// MARK: - Identifiers and keywords

extension UnicodeScalarView {

    /// Parses an identifier conforming to `[_A-Za-z][_A-Za-z0-9-]*`.
    ///
    /// If the resulting name is in `keywords` the token type is `.keyword`;
    /// otherwise it is `.identifier`.
    ///
    /// The head character (`_` or a letter) has already been verified by the
    /// caller; `startIndex` is the position of that character.
    mutating func parseIdentifier(startIndex: Index, keywords: Set<String>) -> Token {
        var name = String(Character(removeFirst()))
        while let c = first,
              CharacterSet.alphanumerics.contains(c) || c == "_" || c == "-" {
            name.append(Character(removeFirst()))
        }
        let type: TokenType = keywords.contains(name) ? .keyword(name) : .identifier(name)
        return Token(type: type, range: startIndex ..< self.startIndex)
    }
}

// MARK: - Numbers

extension UnicodeScalarView {

    /// Parses an integer literal in decimal, hexadecimal (`0x`), octal (`0o`),
    /// or binary (`0b`) notation.
    ///
    /// The leading digit has already been verified by the caller; `startIndex`
    /// is the position of that digit.
    ///
    /// Returns `.invalid(.malformedNumber)` when a recognised prefix (`0x`,
    /// `0o`, `0b`) is present but the digit body is missing or invalid.
    mutating func parseNumber(startIndex: Index) -> Token {

        // Peek at the first two characters to detect a base prefix.
        // We only commit to a prefixed parse when the second character is a
        // known base specifier (`x`, `o`, `b`).
        if first == "0" {
            let saved = self                   // snapshot for potential rollback
            _ = removeFirst()                  // consume '0'

            if let second = first {
                switch second {
                case "x", "X":
                    _ = removeFirst()          // consume 'x'
                    if let digits = readCharacters(where: isHexDigit) {
                        let value = Int(digits, radix: 16) ?? 0
                        return Token(type: .number(.hexadecimal(value)),
                                     range: startIndex ..< self.startIndex)
                    }
                    return Token(type: .invalid(.malformedNumber),
                                 range: startIndex ..< self.startIndex)

                case "o", "O":
                    _ = removeFirst()
                    if let digits = readCharacters(where: isOctalDigit) {
                        let value = Int(digits, radix: 8) ?? 0
                        return Token(type: .number(.octal(value)),
                                     range: startIndex ..< self.startIndex)
                    }
                    return Token(type: .invalid(.malformedNumber),
                                 range: startIndex ..< self.startIndex)

                case "b", "B":
                    _ = removeFirst()
                    if let digits = readCharacters(where: isBinaryDigit) {
                        let value = Int(digits, radix: 2) ?? 0
                        return Token(type: .number(.binary(value)),
                                     range: startIndex ..< self.startIndex)
                    }
                    return Token(type: .invalid(.malformedNumber),
                                 range: startIndex ..< self.startIndex)

                default:
                    // Not a prefixed literal; roll back and fall through to
                    // the plain decimal path (handles bare `0` and `0123…`).
                    self = saved
                }
            } else {
                // Input ended after `0` — it is a valid decimal zero.
                return Token(type: .number(.decimal(0)),
                             range: startIndex ..< self.startIndex)
            }
        }

        // Plain decimal integer.
        let digits = readCharacters(where: isDecimalDigit) ?? "0"
        let value  = Int(digits, radix: 10) ?? 0
        return Token(type: .number(.decimal(value)), range: startIndex ..< self.startIndex)
    }

    // MARK: - Digit predicates

    private func isDecimalDigit(_ s: UnicodeScalar) -> Bool {
        s >= "0" && s <= "9"
    }

    private func isHexDigit(_ s: UnicodeScalar) -> Bool {
        (s >= "0" && s <= "9") ||
        (s >= "a" && s <= "f") ||
        (s >= "A" && s <= "F")
    }

    private func isOctalDigit(_ s: UnicodeScalar) -> Bool {
        s >= "0" && s <= "7"
    }

    private func isBinaryDigit(_ s: UnicodeScalar) -> Bool {
        s == "0" || s == "1"
    }
}

// MARK: - Low-level read helpers

extension UnicodeScalarView {

    /// Reads exactly one scalar if it satisfies `matching`; otherwise returns nil.
    mutating func readCharacter(
        where matching: (UnicodeScalar) -> Bool = { _ in true }
    ) -> UnicodeScalar? {
        guard let c = first, matching(c) else { return nil }
        return removeFirst()
    }

    /// Reads a maximal run of scalars satisfying `matching`.
    /// Returns the matched string, or `nil` if zero characters matched.
    mutating func readCharacters(where matching: (UnicodeScalar) -> Bool) -> String? {
        var idx = startIndex
        while idx < endIndex, matching(self[idx]) {
            idx = index(after: idx)
        }
        guard idx > startIndex else { return nil }
        let matched = String(prefix(upTo: idx))
        self = suffix(from: idx)
        return matched
    }
}
