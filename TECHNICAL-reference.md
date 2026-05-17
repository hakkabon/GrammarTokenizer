# Tokenizer — Technical Reference

This document gives a component-by-component description of the Tokenizer
library's internals: data structures, algorithms, design choices, and the
contracts each piece upholds.

---

## Table of Contents

1. [Architecture overview](#architecture-overview)
2. [Tokenizing protocol](#tokenizing-protocol)
3. [TokenizerCore](#tokenizercore)
4. [Tokenizer](#tokenizer)
5. [GrammarTokenizer](#grammartokenizer)
6. [InputTokenizer](#inputtokenizer)
7. [TokenSequence](#tokensequence)
8. [ParserInput](#parserinput)
9. [TokenizerParser extensions](#tokenizerparser-extensions)
10. [Trie](#trie)
11. [UnicodeScalarView](#unicodescalarview)
12. [TokenType and Numerical](#tokentype-and-numerical)
13. [TokenError](#tokenerror)
14. [Token](#token)
15. [TokenizerUtils](#tokenizerutils)
16. [Data-flow walkthrough](#data-flow-walkthrough)
17. [Error handling strategy](#error-handling-strategy)
18. [Performance notes](#performance-notes)

---

## Architecture overview

```
Source String
     │
     ▼
UnicodeScalarView              — high-performance character cursor
     │
     ├──► Trie.longestMatch()  — O(L) maximum-munch symbol recognition
     │
     ├──► Parser extensions    — literal / comment / identifier / number sub-parsers
     │
     ▼
TokenizerCore.nextToken()      — classifies one token per call (no buffer)
     │
     ▼  implements
Tokenizing (protocol)          — next() · tokenize() · isEmpty · symbols · keywords
     │
     ├── Tokenizer              — general purpose
     ├── GrammarTokenizer       — BNF/EBNF grammar definitions
     └── InputTokenizer         — input text described by a grammar
              │
              │  wrapped by
              ▼
         ParserInput            — lazy lookahead queue for recursive-descent parsers
              │
              ▼
         TokenSequence          — Swift Sequence / IteratorProtocol bridge
```

The central discipline of the design is the strict separation of concerns:

- **Character consumption** lives in `UnicodeScalarView`.
- **Symbol recognition** lives in `Trie`.
- **Token classification** lives in the parser extensions and `nextToken()`.
- **Lookahead buffering** lives exclusively in `ParserInput`.
- **Domain configuration** lives in the concrete subclass constructors.

No layer reaches into the concerns of another.

---

## Tokenizing protocol

**File:** `TokenizerCore.swift`

```swift
public protocol Tokenizing: AnyObject {
    func next() -> Token?
    func tokenize() -> [Token]
    var isEmpty: Bool { get }
    var symbols: Set<String> { get }
    var keywords: Set<String> { get }
}
```

`Tokenizing` is the only type a consuming module needs to import when it does
not care which concrete scanner is in use.  The `AnyObject` constraint is
present because all scanners are reference types; it allows `ParserInput` to
hold the scanner without an existential box.

The protocol intentionally omits `peek` and `consume`.  Those capabilities
belong to `ParserInput`, not to the scanner itself.  This keeps the scanner's
contract minimal and its implementation free of buffer state.

---

## TokenizerCore

**File:** `TokenizerCore.swift`

### Role

`TokenizerCore` is the shared scanning engine.  It owns three pieces of state:
the `UnicodeScalarView` character cursor, the symbol `Trie`, and the keyword
`Set<String>`.  Its single public behaviour is `nextToken()` — consume
characters from the view, classify them, and return one token.

It is declared `open` so that domain-specific subclasses (`GrammarTokenizer`,
`InputTokenizer`, user-defined subclasses) can override `nextToken()` to inject
additional token classes (e.g. indentation tokens, string interpolation
markers) without reimplementing the whole scanning loop.

### Built-in symbol set

```swift
public static let builtInSymbols: Set<String> = [
    ".", ";", ":",
    "'", "\"",          // string literal delimiters
    "#", "//",          // line-comment markers
    "/",                // regex delimiter (and prefix of // and /*)
    "/*", "*/",         // C-style block comment
    "(*", "*)"          // Pascal-style block comment
]
```

These are always registered.  A caller's extra symbols are merged with this set
via `Set.union` in `init`.  Making the set `public static` means callers can
inspect it and subclasses can extend or override it in their own `init`.

### Initialisation

```swift
public init(_ source: String, symbols: Set<String> = [], keywords: Set<String> = [])
```

Three things happen in `init`, in order:

1. The source string is wrapped in a `UnicodeScalarView`.
2. The merged symbol set is computed.
3. The Trie is built by calling `trie.inserting(_:)` once per symbol.

Nothing else.  The character view is not touched — no tokens are produced
until the first `next()` call.  This is a deliberate departure from the
original design, which pre-filled a circular buffer in `init`, causing
`nextToken()` to run at construction time as a hidden side effect.

### `next()` and `nextToken()`

```swift
public final func next() -> Token? { nextToken() }
open func nextToken() -> Token? { … }
```

`next()` is `final` (it is the protocol entry point and must not be overridden).
`nextToken()` is `open` (it is the override point for subclasses).  This
separation means a subclass can customise classification without the risk of
accidentally breaking the `Tokenizing` contract.

### `nextToken()` — scanning algorithm

```
1. skipWhitespace()
2. Guard: return nil if view is empty.
3. Save tokenStart = characters.startIndex
4. Attempt trie.longestMatch(in: &characters)  →  String?
   Matched:
     "'"  or  "\"   →  parseLiteral(startIndex:until:)
     "/"             →  parseRegexDefinition(startIndex:until:)
     "#"  or  "//"  →  parseLineComment(startIndex:)
     "/*"            →  parseBlockComment(startIndex:match:"*/")
     "(*"            →  parseBlockComment(startIndex:match:"*)")
     "*/"  or  "*)" →  Token(.invalid(.unrecognizedInput(symbol)))   ← no fatalError
     anything else  →  Token(.symbol(symbol))
   Not matched:
     first is letter or '_'  →  parseIdentifier(startIndex:keywords:)
     first is '0'..'9'       →  parseNumber(startIndex:)
     otherwise               →  return nil
```

Stray closing comment markers (`*/`, `*)`) now produce an `.invalid` token
rather than calling `fatalError`.  This is a correctness fix: these are
user-input errors, not programmer errors, and `fatalError` is an inappropriate
response to bad input.

### `tokenize()`

Drives `nextToken()` to completion and collects results into an array.  After
the loop, if `characters` is non-empty (meaning at least one character matched
nothing at all), the residual text is wrapped in a single
`.invalid(.unrecognizedInput)` token appended at the end.  This preserves the
invariant that the entire source string is accounted for in the token stream.

---

## Tokenizer

**File:** `Tokenizer.swift`

The fully general concrete scanner.  Adds nothing beyond a clean `override
init` that delegates to `TokenizerCore.init` with the caller's symbols and
keywords.  It is `final` because there is no meaningful way to specialise a
general-purpose scanner further within this hierarchy; domain specialisation is
done at the `TokenizerCore` level.

Use this class when building a new DSL, scanning config files, or any text
scanning task where the vocabulary is known at the call site.

---

## GrammarTokenizer

**File:** `GrammarTokenizer.swift`

Pre-configures the engine for reading BNF and EBNF grammar *definition* files.
The standard BNF/EBNF operator set is registered as a `public static let` so
callers can inspect it:

```swift
public static let bnfSymbols: Set<String> = [
    "::=", "=",         // rule-definition operators
    "|",                // alternation
    "<", ">",           // non-terminal angle brackets
    "(", ")",           // grouping
    "[", "]",           // optional group [ … ]
    "{", "}",           // repetition group { … }
    ",",                // sequence separator
    "+", "*", "?",      // EBNF one-or-more, zero-or-more, zero-or-one
    "-",                // ISO EBNF exception / exclusion
]
```

Extra symbols and keywords for dialect-specific extensions can be passed via
`extraSymbols:` and `extraKeywords:`.  No keywords are registered by default
because BNF grammars typically have no reserved words at the meta level.

---

## InputTokenizer

**File:** `InputTokenizer.swift`

Functionally identical to `Tokenizer`, but its initialiser parameters are
named `terminalSymbols:` and `reservedWords:` rather than `symbols:` and
`keywords:`.  This distinction is entirely about call-site readability: when a
parser driver constructs a scanner from a parsed grammar, the named parameters
make the intent unambiguous.

The two-class design (`Tokenizer` / `InputTokenizer`) avoids overloading one
class with dual roles — "vocabulary specified by the programmer at compile time"
vs. "vocabulary discovered from a grammar at runtime" — which would make the
code harder to reason about even though the underlying mechanism is identical.

---

## TokenSequence

**File:** `TokenizerCore.swift`

```swift
public struct TokenSequence<T: Tokenizing>: Sequence, IteratorProtocol {
    private let tokenizer: T
    public mutating func next() -> Token? { tokenizer.next() }
}
```

This struct replaces the original design where `Tokenizer` conformed to both
`Sequence` and `IteratorProtocol` simultaneously, making the class its own
iterator.  That pattern has a well-known trap: once `for … in` begins
consuming tokens, interleaving direct `next()` calls on the same object
silently skips tokens.  `TokenSequence` is a separate value; the scanner
object remains independent of any iteration in progress.

Because `TokenSequence` holds the scanner as a `let` property (a reference),
it shares the scanner's state: tokens consumed via `TokenSequence` are gone
from the scanner too.  This is deliberate — the scanner is single-pass by
design.

---

## ParserInput

**File:** `ParserInput.swift`

### Role

`ParserInput` is the **only** place in the library where lookahead state lives.
It is a generic `struct` (not a class) because it holds no shared mutable
state; every parser owns its own copy of the queue and should not share it.

```swift
public struct ParserInput<Scanner: Tokenizing> {
    private let scanner:   Scanner
    private var lookahead: [Token] = []
    private let eofRange:  Range<String.Index>
}
```

### Why a struct, not a class?

A parser is typically a local variable or a method parameter.  Owning the
lookahead queue by value makes the ownership model explicit: copying a
`ParserInput` copies the queue, which is the right semantics for checkpointing
or speculative parsing.

### Lazy queue mechanics

```
peek(ahead n:) → Token?
  while lookahead.count < n:
      token = scanner.next()   // may return nil
      if nil: return nil
      lookahead.append(token)
  return lookahead[n - 1]

consume() → Token?
  if !lookahead.isEmpty:
      return lookahead.removeFirst()
  return scanner.next()

get() → Token          // sentinel variant
  return consume() ?? Token(.eof, range: eofRange)
```

Key properties:
- No tokens are produced at `init` time.
- `peek(ahead: 1)` through `peek(ahead: N)` each fill the queue to the
  requested depth on their first call; subsequent calls with the same `n` are
  O(1) array accesses.
- `consume()` drains the front of the queue first, only calling the scanner
  when the queue is empty.  This ensures that tokens peeked at are returned in
  the correct order when consumed.
- `isEmpty` checks both the queue and the scanner, so it is accurate even when
  tokens are buffered.

### Convenience methods

`match(_ type:) -> Bool` — returns `true` and consumes if the next token's type
equals `type`; returns `false` and leaves the stream untouched otherwise.
Covers the common LL(1) "expect exactly this token" pattern.

`accept(_ type:) -> Token?` — like `match`, but returns the token on success
and `nil` on failure.  Useful when the caller needs the token's range or
associated value.

### Comparison with the original circular buffer

| Property | Original `TokenBuffer` | New `ParserInput` |
|---|---|---|
| Buffer size | Fixed at init, `buffer size` parameter | Unbounded, grows on demand |
| Init side effects | `nextToken()` called `size` times during init | No tokens produced at init |
| Max peek depth | `buffer.size - 1`, enforced by `assert` at runtime | No limit |
| Index arithmetic | Modular: `(index + n - 1) % count` | None: plain array index `n - 1` |
| Separation of concerns | Buffer embedded inside `Tokenizer` | Separate type; scanner stays clean |
| Delegate pattern | `TokenBufferDelegate` protocol + `var delegate` on struct | Not needed |

---

## TokenizerParser extensions

**File:** `TokenizerParser.swift`

All sub-parsers are `mutating` extensions on `UnicodeScalarView`.  They now
accept an explicit `startIndex` parameter — the index saved by `nextToken()`
*before* the Trie consumed the opening delimiter — so that every token's range
correctly spans from the opening delimiter to the end of the token body.

### `skipWhitespace()`

Drains leading `CharacterSet.whitespacesAndNewlines` scalars.  Called at the
top of every `nextToken()` invocation.

### `parseLiteral(startIndex:until:) -> Token`

**Bug fixed:** The original computed the range end as
`self.index(self.startIndex, offsetBy: -1)`, which calls `UnicodeScalarView`'s
forward-only `index(_:offsetBy:)` with a negative offset — undefined behaviour
that would crash at runtime.  The fix captures the end index *before* calling
`popFirst()` to consume the closing delimiter:

```swift
if scalar == terminator {
    let endIndex = index(self.startIndex, offsetBy: -1, limitedBy: self.startIndex)
        ?? self.startIndex
    return Token(type: .literal(body), range: startIndex ..< endIndex)
}
```

Returns `.invalid(.unterminatedString(body))` when EOF is reached before the
closing delimiter.

### `parseRegexDefinition(startIndex:until:) -> Token`

Identical structure to `parseLiteral`; produces `.regex(body)`.  Same range
bug fixed by the same technique.

### `parseLineComment(startIndex:) -> Token`

Reads until a newline character is encountered (the newline is left unconsumed).
Returns a comment token with an empty body rather than `nil` when the comment
marker appears at the very end of input with no trailing newline, so the token
stream is never broken.

### `parseBlockComment(startIndex:match:) -> Token`

**Bug fixed:** The original returned `nil` on an unterminated block comment and
then restored `self = start`.  This caused `nextToken()` to fall through to the
identifier/digit branch and attempt to re-parse the `/*` or `(*` characters
as something else, silently producing wrong tokens.

The fix returns `.invalid(.unterminatedString(body))` instead of `nil`:

```swift
// Closing marker never found — unterminated block comment.
return Token(type: .invalid(.unterminatedString(body)), range: startIndex ..< self.startIndex)
```

A secondary fix corrects a character-dropping bug in the matching loop: when
the first closing character is found but the second is not, the original
appended only the second character to the body, silently dropping the first.
The new code appends both:

```swift
if scalar == close[0], let next = popFirst() {
    if next == close[1] { /* matched */ }
    body.append(Character(scalar))   // keep first
    body.append(Character(next))     // keep second
    continue
}
```

### `parseIdentifier(startIndex:keywords:) -> Token`

**Bug fixed:** The original guarded with `CharacterSet.letters.contains(head)`,
meaning a leading `_` would cause `nil` to be returned and `_` would become
unrecognised input, contradicting the documented grammar `[_A-Za-z][_A-Za-z0-9-]*`.

The fix adds `|| first == "_"` to the head predicate in `nextToken()` and
simply calls `removeFirst()` without re-checking the head inside the function,
since the caller has already verified it.

### `parseNumber(startIndex:) -> Token`

**Replaces `parseDigits()`.**  The old function only handled decimal integers
and left the other three `Numerical` cases permanently dead.  The new function:

1. Checks whether the leading character is `0`.
2. If so, peeks at the next character for a base prefix (`x`/`X`, `o`/`O`,
   `b`/`B`).
3. On a recognised prefix, consumes it and reads the appropriate digit body.
4. On an absent or empty digit body after a recognised prefix, returns
   `.invalid(.malformedNumber)`.
5. On any other character after `0` (or no character), rolls back to the
   snapshot and falls through to plain decimal parsing.
6. For non-`0` leading digits, reads a maximal decimal digit run directly.

The snapshot-and-rollback for the `0` case is implemented by saving `let saved
= self` before consuming `0`, allowing the view to be restored without any
separate lookahead mechanism.

### `readCharacter(where:)` and `readCharacters(where:)`

Low-level helpers shared by multiple sub-parsers.  `readCharacters(where:)` no
longer maintains an unused `count` variable.

---

## Trie

**File:** `TokenizerTrie.swift`

### Representation

```swift
public indirect enum Trie<Element: Hashable> {
    case empty
    case node(isTerminating: Bool, children: [Element: Trie<Element>])
}
```

Persistent value type.  The `indirect` keyword places each `.node` on the heap,
making structural sharing across copies safe without reference counting overhead
at the application level.

### Insertion

Purely functional: `inserting(_:)` returns a *new* Trie sharing all unchanged
sub-tries with the receiver.  The recursion is over the sequence's iterator;
at each step it rebuilds only the nodes along the path to the new terminal
node.  The cost is O(L) allocations per inserted symbol, where L is the symbol
length.  Since insertion only happens once, in `TokenizerCore.init`, this cost
is paid exactly once per tokenizer lifetime.

### `longestMatch(in:) -> String?`

**Return type changed from `[Element]?` to `String?`.**  The original `[Element]?`
return had an ambiguity: a non-nil but empty array was indistinguishable from a
zero-length match (which would arise if the Trie root itself were ever marked
as terminating).  `String?` is unambiguous: `nil` means no match, a non-empty
string is the match.

The algorithm walks the Trie and the scalar view simultaneously:

1. At each position, if `currentTrie.isTerminating`, record `(currentIndex,
   currentPath)` as the best match so far.
2. Look up `Character(scalars[currentIndex])` in the current node's children;
   step in if found, break otherwise.
3. After the loop, do one final termination check (handles symbols ending
   exactly at EOF).
4. If `bestMatch` is empty, return `nil` without modifying the view.
5. Otherwise, call `scalars.removeUntil(bestEnd)` — the only mutation of the
   input — and return `bestMatch`.

The dead `#if false` block (~120 lines of an abandoned class-based
implementation) has been removed.

---

## UnicodeScalarView

**File:** `TokenizerUnicodeScalar.swift`

A custom value-type wrapper around `String.UnicodeScalarView` that maintains
two `String.UnicodeScalarView.Index` values (`startIndex`, `endIndex`) into the
*original* backing view.  No characters are ever copied; all slicing operations
produce new views into the same backing storage.

### Why a custom type?

`String.UnicodeScalarView.SubSequence` in Swift 3.2+ is substantially slower
for repeated `popFirst()` calls due to additional bridging layers.  This type
provides a measured ~7× speedup over `SubSequence` for the `popFirst()`-heavy
scanning workload.

### Key operations and their complexities

| Operation | Complexity | Notes |
|---|---|---|
| `first` | O(1) | Read without consuming |
| `isEmpty` | O(1) | Index comparison |
| `popFirst()` | O(1) | Advances `startIndex` by one |
| `removeFirst()` | O(1) | Returns the consumed scalar |
| `removeFirst(_ n:)` | O(n) | `index(_:offsetBy:limitedBy:)` walk |
| `removeUntil(_ index:)` | O(1) | Direct assignment of `startIndex` |
| `prefix(upTo:)` | O(1) | New view with adjusted `endIndex` |
| `suffix(from:)` | O(1) | New view with adjusted `startIndex` |
| `index(after:)` | O(1) | Delegates to backing view |
| `index(_:offsetBy:limitedBy:)` | O(n) | Delegates to backing view |

All mutating operations that would move `startIndex` backwards are rejected by
`precondition`.

---

## TokenType and Numerical

**File:** `TokenizerTokenType.swift`

### TokenType

| Case | Associated value | Produced by |
|---|---|---|
| `.comment(String)` | Comment body | `parseLineComment`, `parseBlockComment` |
| `.eof` | — | `ParserInput.get()` sentinel |
| `.identifier(String)` | Name | `parseIdentifier` (not in keyword set) |
| `.invalid(TokenError)` | Structured error | All sub-parsers on error paths; `tokenize()` for residual input |
| `.keyword(String)` | Name | `parseIdentifier` (name in keyword set) |
| `.literal(String)` | String body | `parseLiteral` |
| `.number(Numerical)` | Numeric value | `parseNumber` |
| `.regex(String)` | Pattern body | `parseRegexDefinition` |
| `.symbol(String)` | Operator text | `nextToken()` default Trie branch |

The `.space(Int)` case has been removed.  Whitespace is always skipped and
never emitted; the case was dead code.  A subclass that requires whitespace
tokens can add its own case and override `nextToken()` to emit it.

### Numerical

```swift
public enum Numerical: Hashable, Equatable, CustomStringConvertible {
    case decimal(Int)
    case hexadecimal(Int)
    case octal(Int)
    case binary(Int)

    public var intValue: Int { … }   // base-independent integer value
}
```

All four cases are now actively produced by `parseNumber()`.  The `intValue`
computed property provides base-independent access to the integer without
pattern matching.  `description` renders the canonical prefix form
(`0x…`, `0o…`, `0b…`) for non-decimal values.

---

## TokenError

**File:** `TokenizerError.swift`

```swift
public enum TokenError: Swift.Error {
    case unexpectedEndOfTokens
    case unrecognizedInput(String)
    case unterminatedString(String)
    case malformedNumber
}
```

**Bug fixed:** The original `Hashable` implementation called `hasher.combine(self)`
for `.unexpectedEndOfTokens` and `.malformedNumber`, causing infinite recursion
at runtime.  The fix uses stable integer discriminants:

```swift
case .unexpectedEndOfTokens: hasher.combine(0)
case .unrecognizedInput(let s): hasher.combine(1); hasher.combine(s)
case .unterminatedString(let s): hasher.combine(2); hasher.combine(s)
case .malformedNumber: hasher.combine(3)
```

The error-as-value design is intentional: the scanner never throws.  Errors
appear as `.invalid(TokenError)` tokens in the normal stream, allowing a parser
to collect multiple diagnostics in one pass.

---

## Token

**File:** `TokenizerToken.swift`

```swift
public struct Token {
    public let type:  TokenType
    public let range: Range<String.Index>
}
```

A lightweight value type.  `range` is a `Range<String.Index>` into the
*original* source `String`.  Use `location(in:)` for integer byte offsets, or
the `lineAndColumn` utilities from `TokenizerUtils` for human-readable
line/column numbers.

`Token` conforms to `CustomStringConvertible`, `Equatable`, and `Hashable`.
Equality requires both `type` and `range` to match, ensuring that two tokens
with the same classification but different source positions are distinct.

---

## TokenizerUtils

**File:** `TokenizerUtils.swift`

### Numeric string conversions

Computed properties on `String` for parsing integers from strings:
`integerValue`, `binaryValue`, `octalValue`, `hexValue` (signed); and the
unsigned counterparts.  The `trim(prefix:)` helper strips known base prefixes
before passing to `Int(_:radix:)`.

The `contains(other:) -> String.Index` method from the original has been
removed.  It shadowed the standard library's `contains(_:) -> Bool` with a
completely different return type and was never called anywhere in the library.

### Source-location utilities

Three utilities for mapping `String.Index` values to human-readable positions.
All are O(n) and should be called lazily, not in token-processing hot loops.

**`String.Index.lineAndColumn(in:)`** — walks from `string.startIndex` to
`self`, counting newlines.  Returns 1-based `(line, column)`.

**`lineAndColumn(for:in:)` (free function)** — finds the line/column of the
*start* of a `Range<String.Index>` within a string.  Stops as soon as the
lower bound is reached.

**`String.lineAndColumn(for:)`** — returns start *and* end line/column for a
range in a single pass.

**Bug fixed (O(n²) → O(n)):** The original instance method used character
enumeration with `self.index(startIndex, offsetBy: index)` inside the loop
body.  Each `offsetBy:` call is itself O(n), making the whole method O(n²).
The rewrite iterates directly over `String.Index` values:

```swift
var current = startIndex
while current <= endIndex {
    if current == range.lowerBound { startLine = line; startColumn = column }
    if current == range.upperBound { endLine = line;   endColumn = column; break }
    if self[current].isNewline { line += 1; column = 1 } else { column += 1 }
    current = index(after: current)
}
```

---

## Data-flow walkthrough

Given the source `rule greeting ::= "hello" ;` with `"rule"` registered as a
keyword via `GrammarTokenizer(source, extraKeywords: ["rule"])`:

1. `GrammarTokenizer.init` calls `TokenizerCore.init`, which builds a Trie from
   the merged symbol set (`GrammarTokenizer.bnfSymbols` ∪ `builtInSymbols`).
   No tokens are produced.

2. A `ParserInput` wraps the scanner.  Its `lookahead` array is empty.

3. First call to `input.peek(ahead: 1)`:
   - Queue has 0 tokens; needs 1 → calls `scanner.next()`.
   - `next()` calls `nextToken()`.
   - `skipWhitespace()` — nothing to skip.
   - `trie.longestMatch` — `r` is not a registered symbol prefix → returns `nil`.
   - `characters.first` is `r`, a letter → `parseIdentifier(startIndex:keywords:)`.
   - Reads `r`, `u`, `l`, `e`; next char is ` ` (space), stops.
   - `"rule"` is in keywords → `Token(.keyword("rule"), range: 0..<4)`.
   - Token appended to queue; `peek` returns it.

4. `input.consume()` — removes `Token(.keyword("rule"))` from the front of the
   queue and returns it.

5. Next `peek` / `consume` cycle: `skipWhitespace()` skips ` `.  Trie matches
   `::=` (maximum munch over `:` and `::`) → `Token(.symbol("::="), …)`.

6. Next cycle: `skipWhitespace()` skips ` `.  Trie matches `"`.  Dispatches
   to `parseLiteral(startIndex:until: "\"")`.  Reads `h`, `e`, `l`, `l`, `o`.
   Finds closing `"` → `Token(.literal("hello"), …)`.

7. And so on until input is exhausted.  `input.get()` returns `Token(.eof, …)`.

---

## Error handling strategy

The library uses a non-throwing, error-as-value design throughout.  Every
possible lexical error produces a `Token` with type `.invalid(TokenError)` and
is inserted into the normal token stream.

Advantages:
- A parser can inspect the complete token stream before deciding how to
  report errors, and can collect multiple errors in one pass.
- Call sites never need `do / try / catch` around the scanner.
- The scanner always produces a complete, well-formed `[Token]` array from
  `tokenize()`.

The only use of Swift's error-propagation machinery was in the conformance to
`Swift.Error` on `TokenError`, which exists so that a parser or application
layer can re-throw the error if it chooses.

`fatalError` has been eliminated from all user-input paths.  The two
`fatalError` calls in the original `nextToken()` (for stray `*/` and `*)`)
are replaced by `.invalid(.unrecognizedInput)` tokens.

---

## Performance notes

- **Character scanning** — `UnicodeScalarView.popFirst()` is O(1) and allocation-free.
- **Symbol matching** — Trie lookup is O(L) where L is the length of the longest
  registered symbol (typically 3 characters), effectively O(1) in practice.
- **Lookahead** — `ParserInput.peek(ahead: n)` is O(k) to fill the queue to
  depth k for the first time, then O(1) for repeat accesses.  `consume()` is
  O(n) for `Array.removeFirst()`, acceptable because the queue never holds
  more than a handful of tokens in any realistic grammar.
- **Keyword lookup** — `Set<String>` membership test is O(1) amortised.
- **Trie construction** — O(S × L) once at `init` time, where S is the number
  of symbols and L is the average symbol length.  Not on any hot path.
- **`lineAndColumn` utilities** — O(n) in the character offset; call lazily
  for diagnostics only.
- **`tokenize()`** — materialises all tokens into an array, O(n) memory.  For
  large inputs, prefer `for token in TokenSequence(scanner)` or the
  `ParserInput` consume loop.
