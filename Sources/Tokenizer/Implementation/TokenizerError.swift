//
//  TokenizerError.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// Structured lexical error values embedded as the associated value of
/// `TokenType.invalid(_:)`.
///
/// The tokenizer uses an *error-as-value* design rather than throwing: it
/// always produces a complete token stream.  Errors appear as
/// `.invalid(TokenError)` tokens mixed into the normal stream, which lets a
/// downstream parser collect multiple diagnostics in one pass.
public enum TokenError: Swift.Error {

    /// The token buffer or parser has consumed all tokens but more were expected.
    case unexpectedEndOfTokens

    /// One or more characters could not be classified into any token.
    case unrecognizedInput(String)

    /// A quoted literal or `/…/` regex reached end-of-input before its
    /// closing delimiter was found.
    case unterminatedString(String)

    /// A numeric literal with a base prefix (`0x`, `0o`, `0b`)
    case malformedNumber
}

extension TokenError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .unexpectedEndOfTokens:
            return "unexpected end of tokens."
        case .unrecognizedInput(let s):
            return "unrecognized '\(s)' in input."
        case .unterminatedString(let s):
            return "unterminated string '\(s)' in input."
        case .malformedNumber:
            return "malformed number literal."
        }
    }
}

extension TokenError: Equatable {

    public static func == (lhs: TokenError, rhs: TokenError) -> Bool {
        switch (lhs, rhs) {
        case (.unexpectedEndOfTokens, .unexpectedEndOfTokens): return true
        case (.unrecognizedInput(let a), .unrecognizedInput(let b)): return a == b
        case (.unterminatedString(let a), .unterminatedString(let b)): return a == b
        case (.malformedNumber, .malformedNumber): return true
        default: return false
        }
    }
}

extension TokenError: Hashable {

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .unexpectedEndOfTokens:
            hasher.combine(0)
        case .unrecognizedInput(let s):
            hasher.combine(1)
            hasher.combine(s)
        case .unterminatedString(let s):
            hasher.combine(2)
            hasher.combine(s)
        case .malformedNumber:
            hasher.combine(3)
        }
    }
}
