//
//  TokenizerToken.swift
//  Tokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

// MARK: - Token

/// A single classified unit of input.
///
/// Every `Token` carries:
///  - `type`  — the semantic category (see `TokenType`).
///  - `range` — the precise `Range<String.Index>` within the *original* source
///              `String` that this token occupies.
///
/// Source-location helpers
/// ───────────────────────
/// `range` stores opaque `String.Index` values.  Use `location(in:)` to
/// convert them to integer byte offsets, or `lineAndColumn(for:in:)` from
/// `TokenizerUtils` for human-readable line/column numbers.
public struct Token {

    public let type:  TokenType
    public let range: Range<String.Index>

    public init(type: TokenType, range: Range<String.Index>) {
        self.type  = type
        self.range = range
    }

    /// Returns the integer byte offsets of the token's start and end positions
    /// within `input`.
    public func location(in input: String) -> (start: Int, end: Int) {
        let start = input.distance(from: input.startIndex, to: range.lowerBound)
        let end   = input.distance(from: input.startIndex, to: range.upperBound)
        return (start: start, end: end)
    }
}

// MARK: - Protocol conformances

extension Token: CustomStringConvertible {
    public var description: String {
        "(\(type) range: \(range))"
    }
}

extension Token: Equatable {
    public static func == (lhs: Token, rhs: Token) -> Bool {
        lhs.type == rhs.type && lhs.range == rhs.range
    }
}

extension Token: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(range)
    }
}
