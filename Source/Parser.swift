// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// A simple parser combinators implementation. "Combinators" mean higher-order
// functions that take one or more parsers as input and produce new parsers like
// output.
//
// See Grammar.swift for the actual regex grammar.

// MARK: - Parser

struct Parser<A> {
    /// Parses the given string. Returns the matched element `A` and the
    /// remaining substring if the match is succesful. Returns `nil` otherwise.
    let parse: (_ string: Substring) throws -> (A, Substring)?
}

extension Parser {
    func parse(_ string: String) throws -> A? {
        try parse(string[...])?.0
    }
}

struct ParserError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        "\(message)"
    }
}

// MARK: - Parser (Predifined)

struct Parsers {}

extension Parsers {
    /// Matches the given string.
    static func string(_ p: String) -> Parser<Void> {
        Parser { str in
            str.hasPrefix(p) ? ((), str.dropFirst(p.count)) : nil
        }
    }

    /// Matches any single character.
    static let char = Parser<Character> { str in
        str.isEmpty ? nil : (str.first!, str.dropFirst())
    }

    /// Matches a character if the given string doesn't contain it.
    static func char(excluding string: String) -> Parser<Character> {
        char.filter { !string.contains($0) }
    }

    /// Matches any character contained in the given string.
    static func char(from string: String) -> Parser<Character> {
        char.filter(string.contains)
    }

    /// Matches characters while the given string doesn't contain them.
    static func string(excluding string: String) -> Parser<String> {
        char(excluding: string).oneOrMore.map { String($0) }
    }

    /// Parsers a natural number or zero. Valid inputs: "0", "1", "10".
    static let number = digit.oneOrMore.map { Int(String($0)) }

    /// Matches a single digit.
    static let digit = char.filter(CharacterSet.decimalDigits.contains)
}

extension Parser: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral where A == Void {
    // Unfortunately had to add these explicitly supposably because of the
    // conditional conformance limitations.
    typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    typealias UnicodeScalarLiteralType = StringLiteralType
    typealias StringLiteralType = String

    init(stringLiteral value: String) {
        self = Parsers.string(value)
    }
}

// MARK: - Parser (Combinators)

/// Matches only if both of the given parsers produced a result.
func zip<A, B>(_ a: Parser<A>, _ b: Parser<B>) -> Parser<(A, B)> {
    a.flatMap { matchA in b.map { matchB in (matchA, matchB) } }
}

func zip<A, B, C>(_ a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>) -> Parser<(A, B, C)> {
    zip(a, zip(b, c)).map { a, bc in (a, bc.0, bc.1) }
}

func zip<A, B, C, D>(_ a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>, _ d: Parser<D>) -> Parser<(A, B, C, D)> {
    zip(a, zip(b, c, d)).map { a, bcd in (a, bcd.0, bcd.1, bcd.2) }
}

func zip<A, B, C, D, E>(_ a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>, _ d: Parser<D>, _ e: Parser<E>) -> Parser<(A, B, C, D, E)> {
    zip(a, zip(b, c, d, e)).map { a, bcde in (a, bcde.0, bcde.1, bcde.2, bcde.3) }
}

/// Returns the first match or `nil` if no matches are found.
func oneOf<A>(_ parsers: Parser<A>...) -> Parser<A> {
    precondition(!parsers.isEmpty)
    return Parser<A> { str -> (A, Substring)? in
        for parser in parsers {
            if let match = try parser.parse(str) {
                return match
            }
        }
        return nil
    }
}

extension Parser {
    func map<B>(_ transform: @escaping (A) throws -> B?) -> Parser<B> {
        flatMap { match in
            Parser<B> { str in
                (try transform(match)).map { ($0, str) }
            }
        }
    }

    func flatMap<B>(_ transform: @escaping (A) throws -> Parser<B>) -> Parser<B> {
        Parser<B> { str in
            guard let (a, str) = try self.parse(str) else { return nil }
            return try transform(a).parse(str)
        }
    }

    func filter(_ predicate: @escaping (A) -> Bool) -> Parser<A> {
        map { predicate($0) ? $0 : nil }
    }
}

// MARK: - Parser (Quantifiers)

extension Parser {
    /// Matches the given parser zero or more times.
    var zeroOrMore: Parser<[A]> {
        Parser<[A]> { str in
            var str = str
            var matches = [A]()
            while let (match, newStr) = try self.parse(str) {
                matches.append(match)
                str = newStr
            }
            return (matches, str)
        }
    }

    /// Matches the given parser one or more times.
    var oneOrMore: Parser<[A]> {
        zeroOrMore.map { $0.isEmpty ? nil : $0 }
    }

    /// Matches of the parser produces no matches (inverts the parser).
    var zero: Parser<Void> {
        map { _ in nil }
    }
}

// MARK: - Parser (Optional)

func optional<A>(_ parser: Parser<A>) -> Parser<A?> {
    Parser<A?> { str -> (A?, Substring)? in
          guard let match = try parser.parse(str) else {
              return (nil, str) // Return empty match without consuming any characters
          }
          return match
      }
}

func optional(_ parser: Parser<Void>) -> Parser<Bool> {
    Parser<Bool> { str -> (Bool, Substring)? in
        guard let match = try parser.parse(str) else {
            return (false, str) // Return empty match without consuming any characters
        }
        return (true, match.1)
    }
}

// MARK: - Parser (Error Reporting)

extension Parser {

    /// Throws an error with the given message if the parser fails to produce a match.
    func orThrow(_ message: String) -> Parser {
        Parser { str -> (A, Substring)? in
            guard let match = try self.parse(str) else {
                throw ParserError(message)
            }
            return match
        }
    }

    /// Matches if the parser produces no matches. Throws an error otherwise.
    func zeroOrThrow<B>(_ message: String) -> Parser<B> {  // automatically cast
        map { _ in throw ParserError(message) }
    }
}

// MARK: - Parser (Misc)

extension Parsers {

    /// Succeeds when input is empty.
    static let end = Parser<Void> { str in str.isEmpty ? ((), str) : nil }

    /// Delays the creation of parser. Use it to break dependency cycles when
    /// creating recursive parsers.
    static func lazy<A>(_ closure: @autoclosure @escaping () -> Parser<A>) -> Parser<A> {
        Parser { str in
            try closure().parse(str)
        }
    }
}

// MARK: - Parser (Operators)

infix operator *> : CombinatorPrecedence
infix operator <* : CombinatorPrecedence
infix operator <*> : CombinatorPrecedence

func *> <A, B>(_ lhs: Parser<A>, _ rhs: Parser<B>) -> Parser<B> {
    zip(lhs, rhs).map { $0.1 }
}

func <* <A, B>(_ lhs: Parser<A>, _ rhs: Parser<B>) -> Parser<A> {
    zip(lhs, rhs).map { $0.0 }
}

func <*> <A, B>(_ lhs: Parser<A>, _ rhs: Parser<B>) -> Parser<(A, B)> {
    zip(lhs, rhs)
}

precedencegroup CombinatorPrecedence {
    associativity: left
    higherThan: DefaultPrecedence
}
