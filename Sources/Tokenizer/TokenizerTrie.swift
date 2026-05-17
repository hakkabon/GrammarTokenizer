//
//  TokenizerTrie.swift
//  Tokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//
//  Changes from the original implementation
//  ─────────────────────────────────────────
//  • longestMatch(in:) now returns `String?` instead of `[Element]?`.
//    The original return type was ambiguous: a non-nil but *empty* array was
//    indistinguishable from a zero-length match.  A `String?` is unambiguous.
//  • Removed the large `#if false` dead-code block (≈ 120 lines).

import Foundation

// MARK: - Trie

/// An immutable, persistent, recursive Trie (prefix tree).
///
/// Used for maximum-munch symbol matching: given the set of registered symbol
/// strings the Trie finds the longest symbol that is a prefix of the current
/// character view.
///
/// The enum is `indirect` so node-level sharing is safe across copies of the
/// value.  Because the Trie is built once at `TokenizerCore.init` time and
/// never mutated afterwards, the functional insertion cost is paid only once.
public indirect enum Trie<Element: Hashable> {
    case empty
    case node(isTerminating: Bool, children: [Element: Trie<Element>])
}

// MARK: - Insertion

extension Trie {

    /// Returns a **new** Trie that contains `sequence`, sharing all unchanged
    /// sub-tries with the receiver.
    public func inserting<S: Sequence>(_ sequence: S) -> Trie<Element>
    where S.Element == Element {
        var iter = sequence.makeIterator()
        return inserting(&iter)
    }

    private func inserting<I: IteratorProtocol>(_ iterator: inout I) -> Trie<Element>
    where I.Element == Element {
        guard let head = iterator.next() else {
            // End of sequence — mark this node as terminating.
            switch self {
            case .empty:
                return .node(isTerminating: true, children: [:])
            case .node(_, let children):
                return .node(isTerminating: true, children: children)
            }
        }

        var children: [Element: Trie<Element>] = switch self {
            case .node(_, let c): c
            case .empty:          [:]
        }

        children[head] = children[head, default: .empty].inserting(&iterator)

        return .node(isTerminating: isTerminating, children: children)
    }

    var isTerminating: Bool {
        guard case .node(let t, _) = self else { return false }
        return t
    }
}

// MARK: - Word enumeration

extension Trie {

    /// All valid sequences (words) stored in the Trie.
    /// Useful for debugging and verification.
    public var words: [[Element]] {
        func discover(_ node: Trie<Element>, path: [Element]) -> [[Element]] {
            guard case let .node(isTerminating, children) = node else { return [] }
            var results = isTerminating ? [path] : []
            for (element, child) in children {
                results += discover(child, path: path + [element])
            }
            return results
        }
        return discover(self, path: [])
    }
}

// MARK: - Maximum-munch match

extension Trie where Element == Character {

    /// Finds the longest registered symbol that is a prefix of `scalars`.
    ///
    /// - Returns: The matched symbol as a `String`, or `nil` if no registered
    ///   symbol is a prefix of the current view.
    /// - Side effect: Advances `scalars.startIndex` past the matched symbol.
    ///   The view is **not** modified if `nil` is returned.
    ///
    /// Returning `String?` (rather than the original `[Element]?`) eliminates
    /// the ambiguity between "no match" (nil) and "matched the empty string"
    /// (non-nil empty array), which could arise if the Trie root itself were
    /// ever marked as terminating.
    public func longestMatch(in scalars: inout UnicodeScalarView) -> String? {
        var currentTrie    = self
        var bestEnd        = scalars.startIndex
        var bestMatch      = ""          // the longest successful match so far
        var currentIndex   = scalars.startIndex
        var currentPath    = ""

        while currentIndex < scalars.endIndex {
            // Record a new best if this node terminates a valid symbol.
            if currentTrie.isTerminating {
                bestEnd   = currentIndex
                bestMatch = currentPath
            }

            let ch = Character(scalars[currentIndex])
            guard case let .node(_, children) = currentTrie,
                  let nextTrie = children[ch] else { break }

            currentPath.append(ch)
            currentTrie  = nextTrie
            currentIndex = scalars.index(after: currentIndex)
        }

        // Final termination check (handles symbols that end exactly at EOF).
        if currentTrie.isTerminating {
            bestEnd   = currentIndex
            bestMatch = currentPath
        }

        guard !bestMatch.isEmpty else { return nil }

        // Advance the view past the matched symbol.
        scalars.removeUntil(bestEnd)
        return bestMatch
    }
}
