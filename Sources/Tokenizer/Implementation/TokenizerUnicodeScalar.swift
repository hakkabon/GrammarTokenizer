//
//  TokenizerUnicodeScalar.swift
//  GrammarTokenizer
//
//  Original implementation by Nick Lockwood, © 2017.
//  Adapted by Ulf Akerstedt-Inoue, © 2026 hakkabon software.
//
//  A high-performance drop-in cursor over `String.UnicodeScalarView`.
//
//  Why a custom type?
//  ──────────────────
//  As of Swift 3.2, `String.UnicodeScalarView.SubSequence` is substantially
//  slower for repeated `popFirst()` calls because it bridges through additional
//  abstraction layers.  This type eliminates that overhead by maintaining two
//  `Index` values into the *original* backing view — no characters are ever
//  copied.
//
//  Benchmarks showed ~7× faster `popFirst()` than SubSequence in Swift 4.

import Foundation

// MARK: - UnicodeScalarView

public struct UnicodeScalarView {

    public typealias Index = String.UnicodeScalarView.Index

    private let characters: String.UnicodeScalarView
    public private(set) var startIndex: Index
    public private(set) var endIndex:   Index

    // MARK: - Construction

    public init(_ unicodeScalars: String.UnicodeScalarView) {
        characters = unicodeScalars
        startIndex = characters.startIndex
        endIndex   = characters.endIndex
    }

    public init(_ string: String) {
        self.init(string.unicodeScalars)
    }

    // MARK: - Basic queries

    public var first: UnicodeScalar? {
        isEmpty ? nil : characters[startIndex]
    }

    public var isEmpty: Bool { startIndex == endIndex }

    /// The current window as a `Range<String.Index>`.
    public var range: Range<String.Index> { startIndex ..< endIndex }

    // MARK: - Subscript / slicing

    public subscript(_ index: Index) -> UnicodeScalar {
        characters[index]
    }

    public subscript(r: Range<Index>) -> UnicodeScalarView {
        var v = UnicodeScalarView(characters)
        v.startIndex = r.lowerBound
        v.endIndex   = r.upperBound
        return v
    }

    public subscript(r: ClosedRange<Index>) -> UnicodeScalarView {
        var v = UnicodeScalarView(characters)
        v.startIndex = r.lowerBound
        v.endIndex   = r.upperBound
        return v
    }

    // MARK: - Index arithmetic

    public func index(after i: Index) -> Index {
        characters.index(after: i)
    }

    public func index(_ i: Index, offsetBy n: Int) -> Index {
        characters.index(i, offsetBy: n)
    }

    /// Returns the index `n` positions after `i`, or `limit` if that would
    /// go past it.  Returns `nil` when the result equals `limit`.
    public func index(
        _ i: Index, offsetBy n: Int, limitedBy limit: Index
    ) -> Index? {
        characters.index(i, offsetBy: n, limitedBy: limit)
    }

    // MARK: - Slicing

    public func prefix(upTo index: Index) -> UnicodeScalarView {
        precondition(index >= startIndex, "prefix(upTo:): index before startIndex")
        precondition(index <= endIndex,   "prefix(upTo:): index past endIndex")
        var v = UnicodeScalarView(characters)
        v.startIndex = startIndex
        v.endIndex   = index
        return v
    }

    public func suffix(from index: Index) -> UnicodeScalarView {
        precondition(index >= startIndex, "suffix(from:): index before startIndex")
        precondition(index <= endIndex,   "suffix(from:): index past endIndex")
        var v = UnicodeScalarView(characters)
        v.startIndex = index
        v.endIndex   = endIndex
        return v
    }

    public func dropFirst() -> UnicodeScalarView {
        var v = UnicodeScalarView(characters)
        v.startIndex = characters.index(after: startIndex)
        v.endIndex   = endIndex
        return v
    }

    // MARK: - Mutation

    /// The remaining scalars as a `SubSequence` of the original view.
    public var unicodeScalars: String.UnicodeScalarView.SubSequence {
        characters[startIndex ..< endIndex]
    }

    /// Removes and returns the next scalar, or `nil` when empty.
    public mutating func popFirst() -> UnicodeScalar? {
        guard !isEmpty else { return nil }
        let c = characters[startIndex]
        startIndex = characters.index(after: startIndex)
        return c
    }

    /// Removes the next scalar and returns it.
    /// Precondition: the view must not be empty.
    @discardableResult
    public mutating func removeFirst() -> UnicodeScalar {
        precondition(!isEmpty, "removeFirst() called on empty UnicodeScalarView")
        let old = startIndex
        startIndex = characters.index(after: startIndex)
        return characters[old]
    }

    /// Advances `startIndex` by `n` scalars.
    /// Precondition: `n ≥ 0` and `n` must not exceed the number of remaining scalars.
    public mutating func removeFirst(_ n: Int) {
        precondition(n >= 0, "removeFirst(_:): n must be non-negative")
        guard let newIndex = characters.index(
            startIndex, offsetBy: n, limitedBy: endIndex
        ) else {
            preconditionFailure("removeFirst(\(n)): not enough scalars remaining")
        }
        startIndex = newIndex
    }

    /// Jumps `startIndex` directly to `index`.
    /// Used by `Trie.longestMatch` to advance the view after a successful match.
    public mutating func removeUntil(_ index: Index) {
        precondition(index >= startIndex, "removeUntil(_:): index before startIndex")
        precondition(index <= endIndex,   "removeUntil(_:): index past endIndex")
        startIndex = index
    }
}

// MARK: - String / SubSequence bridges

typealias _UnicodeScalarView = UnicodeScalarView

extension String {
    init(_ view: _UnicodeScalarView) {
        self.init(view.unicodeScalars)
    }
}

extension Substring.UnicodeScalarView {
    init(_ view: _UnicodeScalarView) {
        self.init(view.unicodeScalars)
    }
}
