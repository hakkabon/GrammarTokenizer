# Tokenizer

A Swift tokenizer (lexer) library built around a clean protocol hierarchy, a
shared scanning engine, and a separate lazy lookahead queue.  The library is
designed around two primary use cases — reading BNF/EBNF grammar *definitions*
and lexing the *input text* that a grammar describes — while remaining fully
general for any structured text scanning task.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Overview

`Tokenizer` converts a raw source string into a typed stream of `Token` values.
Each token carries its semantic category (`identifier`, `keyword`, `symbol`,
`literal`, `number`, `comment`, `regex`, or an error) together with a
`Range<String.Index>` that locates it precisely within the original input.

Three concrete tokenizer classes cover the main use cases out of the box, all
built on the same shared `TokenStream` engine:

- **`GrammarTokenizer`** — pre-configured for reading BNF/EBNF grammar *definitions*.
  No boilerplate; just pass the grammar source string.
- **`InputTokenizer`** — configured at runtime from a grammar's terminal set.
  Used to lex the *input text* that a BNF grammar describes, closing the loop
  between grammar parsing and input parsing.
- **`Tokenizer`** — the fully general form.  The caller supplies any symbol set
  and keyword list, making it suitable for any DSL, config file, or log
  scanning task.

Lookahead and parser interaction are handled by a separate `ParserInput` value
type, keeping the scanners themselves free of buffer state entirely.

---

## Key Features

- **Protocol-based hierarchy** — `Tokenizing` is the public contract; `TokenStream`
  is the shared `open class` engine; all three concrete classes are thin
  subclasses that contribute only initialiser defaults.
- **No buffer in the scanner** — `TokenStream` is a pure scanner.  All lookahead
  state lives exclusively in `ParserInput`, which is only created when a parser
  needs it.
- **Lazy lookahead queue** — `ParserInput` fills its internal queue on demand as
  `peek(ahead:)` is called.  There is no fixed maximum lookahead depth and no
  tokens are produced at construction time.
- **Configurable symbols and keywords** — each tokenizer merges caller-supplied
  symbols with a built-in set that handles literals, comments, and regex
  delimiters automatically.
- **Maximum-munch symbol matching** — overlapping symbols (e.g. `/` vs `//` vs
  `/*`) are resolved correctly by always preferring the longest possible match,
  using an immutable persistent Trie.
- **Full integer literal coverage** — `parseNumber` recognises decimal, hex (`0x`),
  octal (`0o`), and binary (`0b`) literals, emitting the appropriate `Numerical`
  case.
- **Correct source ranges** — every `Token` records the exact
  `Range<String.Index>` in the original `String`.  Range-computation bugs
  present in earlier versions (negative-offset index crash, wrong block-comment
  end index) are fixed.
- **Error-as-value, no throwing** — malformed input produces `.invalid(TokenError)`
  tokens in the normal stream.  Unterminated block comments and stray closing
  comment markers are handled gracefully rather than crashing.
- **`TokenSequence` bridge** — a separate generic struct wraps any `Tokenizing`
  scanner as a Swift `Sequence`, avoiding the single-pass ordering bugs of the
  old self-as-iterator design.
- **Fast character scanning** — the custom `UnicodeScalarView` is measurably
  faster than `String.UnicodeScalarView.SubSequence` for repeated `popFirst()`
  operations.

---

## Components

| File | Type | Purpose |
|---|---|---|
| `TokenStream.swift` | `open class` + `protocol` + `struct` | `Tokenizing` protocol, shared scanning engine, `TokenSequence` bridge |
| `Tokenizer.swift` | `final class` | General-purpose tokenizer; caller supplies symbols + keywords |
| `GrammarTokenizer.swift` | `final class` | Pre-configured for BNF/EBNF grammar definitions |
| `InputTokenizer.swift` | `final class` | Runtime-configured from a grammar's terminal set |
| `ParserInput.swift` | `struct` | Lazy lookahead queue; wraps any `Tokenizing` scanner |
| `TokenizerToken.swift` | `struct` | `Token`: type + source range + location helpers |
| `TokenizerTokenType.swift` | `enum` | `TokenType` and `Numerical` — the token taxonomy |
| `TokenizerError.swift` | `enum` | `TokenError` — structured lexical error values |
| `TokenizerTrie.swift` | `indirect enum` | Immutable persistent Trie for symbol matching |
| `TokenizerParser.swift` | extensions | Sub-parsers for literals, comments, identifiers, numbers, regex |
| `TokenizerUnicodeScalar.swift` | `struct` | High-performance character cursor |
| `TokenizerUtils.swift` | extensions | Numeric conversions, line/column source-location utilities |

---

## Usage Examples

### Use case 1 — Reading a BNF grammar definition

```swift
import Foundation

let grammarSource = """
rule greeting ::= "Hello" | "Hi" ;
// simple BNF rule
(* block comment *)
rule farewell ::= "Bye" | "Goodbye" ;
"""

let tokenizer = GrammarTokenizer(grammarSource)

// Lazy iteration:
for token in TokenSequence(tokenizer) {
    print(token)
}

// Or collect eagerly:
let tokens = GrammarTokenizer(grammarSource).tokenize()
```

### Use case 2 — Lexing input text described by a grammar

After a BNF grammar has been parsed, create an `InputTokenizer` from the
terminal symbols the grammar produced:

```swift
// Terminals and reserved words extracted from the parsed grammar.
let terminals: Set<String> = ["+", "-", "*", "/", "(", ")", "=", ";"]
let reserved:  Set<String> = ["if", "then", "else", "while", "do", "end"]

let inputSource = "if x = 42 then y = x + 1 ;"

let scanner = InputTokenizer(
    inputSource,
    terminalSymbols: terminals,
    reservedWords:   reserved
)
let tokens = scanner.tokenize()
```

### Use case 3 — General-purpose scanning

```swift
let scanner = Tokenizer(
    source,
    symbols:  ["->", "=>", ":", ",", "(", ")"],
    keywords: ["type", "case", "of", "let", "in"]
)
let tokens = scanner.tokenize()
```

### Use case 4 — Parser with lookahead

Wrap any scanner in `ParserInput` when a recursive-descent parser needs
`peek` and `consume`:

```swift
let source  = "rule greeting ::= \"hello\" ;"
let scanner = GrammarTokenizer(source, extraKeywords: ["rule"])
var input   = ParserInput(scanner, source: source)

// Peek without consuming:
if input.peek()?.type == .keyword("rule") {
    input.consume()                          // discard "rule"
    let name   = input.consume()             // grab rule name
    input.match(.symbol("::="))              // consume "::=" or leave stream intact
    let rhs    = input.consume()             // grab the right-hand side
    input.match(.symbol(";"))
}

// Deeper lookahead (unbounded):
if input.peek(ahead: 2)?.type == .symbol("::=") { … }

// Sentinel-based loop (no optionals):
while true {
    let token = input.get()                  // returns .eof when exhausted
    if token.type == .eof { break }
    process(token)
}
```

### Sample token output

For the input `rule greeting ::= "hello" ;` with `"rule"` as a keyword:

```
(keyword: 'rule'     range: ...)
(identifier: 'greeting'  range: ...)
(symbol: '::='       range: ...)
(literal: 'hello'    range: ...)
(symbol: ';'         range: ...)
```

---

## Installing

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/Tokenizer.git", from: "2.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Tokenizer"]
    )
]
```

```swift
import Tokenizer
```

### Manual installation

Copy all `.swift` files into your Xcode project or Swift package:

```
TokenStream.swift
Tokenizer.swift
GrammarTokenizer.swift
InputTokenizer.swift
ParserInput.swift
TokenizerToken.swift
TokenizerTokenType.swift
TokenizerError.swift
TokenizerTrie.swift
TokenizerParser.swift
TokenizerUnicodeScalar.swift
TokenizerUtils.swift
```

No external dependencies — the library uses `Foundation` only.

### Requirements

| | |
|---|---|
| Swift | 5.9 or later |
| Platforms | macOS 13+, iOS 16+, tvOS 16+, watchOS 9+ |
| Dependencies | Foundation only |

---

## License

Copyright © 2019–2026 hakkabon software. All rights reserved.
