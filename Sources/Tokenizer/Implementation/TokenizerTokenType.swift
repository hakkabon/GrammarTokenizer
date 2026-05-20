//
//  TokenizerTokenType.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

public enum TokenType: Equatable, Hashable {

    /// Single-line (`//`, `#`) or block (`/* */`, `(* *)`) comment body.
    case comment(String)

    /// End-of-input sentinel.
    case eof

    /// An unquoted name: `[_A-Za-z][_A-Za-z0-9-]*`
    case identifier(String)

    /// An unclassifiable or malformed input sequence.
    case invalid(TokenError)

    /// An identifier that matches a caller-supplied reserved word.
    case keyword(String)

    /// A quoted string: `'…'` or `"…"`
    case literal(String)

    /// An integer literal in decimal, hex, octal, or binary notation.
    case number(Numerical)

    /// A forward-slash-delimited regular expression body: `/…/`
    case regex(String)

    /// A registered operator / punctuation symbol.
    case symbol(String)

    /// The token's string payload, uniform across all cases.
    public var value: String {
        switch self {
        case .comment(let s):    return s
        case .eof:               return "¶"
        case .identifier(let s): return s
        case .invalid(let e):    return "\(e)"
        case .keyword(let s):    return s
        case .literal(let s):    return s
        case .number(let n):     return "\(n)"
        case .regex(let s):      return s
        case .symbol(let s):     return s
        }
    }
}

// MARK: - CustomStringConvertible

extension TokenType: CustomStringConvertible {

    public var description: String {
        switch self {
        case .comment(let s):    return "comment: '\(s)'"
        case .eof:               return "eof: ¶"
        case .identifier(let s): return "identifier: '\(s)'"
        case .invalid(let e):    return "invalid: '\(e)'"
        case .keyword(let s):    return "keyword: '\(s)'"
        case .literal(let s):    return "literal: '\(s)'"
        case .number(let n):     return "number: '\(n)'"
        case .regex(let s):      return "regex: '\(s)'"
        case .symbol(let s):     return "symbol: '\(s)'"
        }
    }
}

// MARK: - Numerical

/// The four integer literal bases supported by `parseNumber()`.
public enum Numerical: Hashable, Equatable, CustomStringConvertible {

    case decimal(Int)
    case hexadecimal(Int)
    case octal(Int)
    case binary(Int)

    /// The underlying integer value, regardless of base.
    public var intValue: Int {
        switch self {
        case .decimal(let v),
             .hexadecimal(let v),
             .octal(let v),
             .binary(let v):
            return v
        }
    }

    public var description: String {
        switch self {
        case .decimal(let v):     return "\(v)"
        case .hexadecimal(let v): return "0x\(String(v, radix: 16, uppercase: false))"
        case .octal(let v):       return "0o\(String(v, radix: 8))"
        case .binary(let v):      return "0b\(String(v, radix: 2))"
        }
    }
}
