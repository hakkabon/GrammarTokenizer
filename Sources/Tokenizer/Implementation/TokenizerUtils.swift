//
//  TokenizerUtils.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

// MARK: - Numeric string conversions

extension String {

    // MARK: - Prefix helpers

    /// Returns the string with `prefix` removed, or the string unchanged if
    /// the prefix is absent.
    func trim(prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    var binaryPrefix: String { "0b" }
    var octalPrefix:  String { "0o" }
    var hexPrefix:    String { "0x" }

    // MARK: - Signed conversions

    var integerValue:         Int? { Int(self, radix: 10) }
    var binaryValue:          Int? { Int(trim(prefix: binaryPrefix), radix: 2)  }
    var octalValue:           Int? { Int(trim(prefix: octalPrefix),  radix: 8)  }
    var hexValue:             Int? { Int(trim(prefix: hexPrefix).trim(prefix: "0X"), radix: 16) }

    // MARK: - Unsigned conversions

    var unsignedIntegerValue: UInt? { UInt(self, radix: 10) }
    var unsignedBinaryValue:  UInt? { UInt(trim(prefix: binaryPrefix), radix: 2) }
    var unsignedOctalValue:   UInt? { UInt(trim(prefix: octalPrefix),  radix: 8) }
    var unsignedHexValue:     UInt? { UInt(trim(prefix: hexPrefix).trim(prefix: "0X"), radix: 16) }
}

// MARK: - Source-location utilities

// All three utilities are O(n) in the distance from the start of the string to
// the target index.  Call them lazily — e.g. only when formatting a diagnostic
// message — not on every token in a hot loop.

extension String.Index {

    /// Returns the 1-based line and column of this index within `string`.
    ///
    /// O(n) in the character offset of the index.
    public func lineAndColumn(in string: String) -> (line: Int, column: Int) {
        var line   = 1
        var column = 1
        let scalars = string.unicodeScalars
        var current = scalars.startIndex

        while current < self {
            if CharacterSet.newlines.contains(scalars[current]) {
                line  += 1
                column = 1
            } else {
                column += 1
            }
            current = scalars.index(after: current)
        }
        return (line: line, column: column)
    }
}

/// Returns the 1-based line and column of the *start* of `range` within
/// `string`.
///
/// O(n) — stops as soon as the lower bound is reached.
public func lineAndColumn(for range: Range<String.Index>, in string: String) -> (line: Int, column: Int) {
    guard !range.isEmpty else { return (1, 1) }

    var line    = 1
    var column  = 1
    var current = string.startIndex

    while current < string.endIndex {
        if current == range.lowerBound { return (line, column) }
        if string[current] == "\n" {
            line  += 1
            column = 1
        } else {
            column += 1
        }
        current = string.index(after: current)
    }
    return (line, column)
}

extension String {

    /// Returns the 1-based start *and* end line/column for `range` within
    /// `self`.
    ///
    /// O(n) — iterates using `String.Index`, not character enumeration with
    /// `index(startIndex, offsetBy:)` in the loop body (that would be O(n²)).
    public func lineAndColumn(
        for range: Range<String.Index>
    ) -> (startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {

        guard !range.isEmpty,
              range.lowerBound >= startIndex,
              range.upperBound <= endIndex
        else { return (1, 1, 1, 1) }

        var line        = 1
        var column      = 1
        var startLine   = 1
        var startColumn = 1
        var endLine     = 1
        var endColumn   = 1
        var current     = startIndex

        while current <= endIndex {
            if current == range.lowerBound {
                startLine   = line
                startColumn = column
            }
            if current == range.upperBound {
                endLine   = line
                endColumn = column
                break
            }
            guard current < endIndex else { break }
            if self[current].isNewline {
                line  += 1
                column = 1
            } else {
                column += 1
            }
            current = index(after: current)
        }

        return (startLine, startColumn, endLine, endColumn)
    }
}
