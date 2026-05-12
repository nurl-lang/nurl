# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL Lexer — tokenizes .nu source files.

Token types follow the grammar spec (spec/grammar.ebnf).
Reserved words: i u f b s v  (type keywords)
                T F           (boolean literals)
All others are IDENT.
"""

from __future__ import annotations
from dataclasses import dataclass
from enum import Enum, auto
from typing import List


class TT(Enum):
    """Token type."""
    # Sigils / punctuation
    AT       = auto()   # @  function def
    COLON    = auto()   # :  binding / struct / const
    ASSIGN   = auto()   # =  assignment statement
    DOLLAR   = auto()   # $  import
    ARROW    = auto()   # →  or ->  return type separator

    # Delimiters
    LBRACE   = auto()   # {
    RBRACE   = auto()   # }
    LPAREN   = auto()   # (  function call
    RPAREN   = auto()   # )
    LBRACKET = auto()   # [  slice type prefix / generic param open
    RBRACKET = auto()   # ]  generic param close

    # Binary operators (all arity-2, prefix in expressions)
    PLUS     = auto()   # +
    MINUS    = auto()   # -
    STAR     = auto()   # *
    SLASH    = auto()   # /
    PERCENT  = auto()   # %
    LT       = auto()   # <
    GT       = auto()   # >
    EQ       = auto()   # ==
    NEQ      = auto()   # !=
    LEQ      = auto()   # <=
    GEQ      = auto()   # >=
    SHL      = auto()   # <<  shift left
    SHR      = auto()   # >>  arithmetic shift right
    AMP      = auto()   # &
    PIPE     = auto()   # |

    # Unary operators (arity-1, prefix)
    BANG     = auto()   # !  logical not
    CARET    = auto()   # ^  return
    TILDE    = auto()   # ~  bitnot / negate  (or loop when followed by block)

    # Special expression operators
    DOT      = auto()   # .  member access
    HASH     = auto()   # #  cast
    QUESTION = auto()   # ?  conditional  (or opt type prefix)
    BACKSLASH = auto()  # \  try operator / closure prefix

    # Literals
    INT      = auto()
    FLOAT    = auto()
    STR      = auto()   # backtick-delimited
    BOOL     = auto()   # T or F

    # Type keywords (reserved; cannot be used as identifiers)
    TYPE_KW  = auto()   # i u f b s v

    # Identifiers
    IDENT    = auto()

    # End of file
    EOF      = auto()


# Maps a single operator character to its TT (no lookahead needed).
_SINGLE: dict[str, TT] = {
    '@': TT.AT,
    ':': TT.COLON,
    '$': TT.DOLLAR,
    '{': TT.LBRACE,
    '}': TT.RBRACE,
    '(': TT.LPAREN,
    ')': TT.RPAREN,
    '[': TT.LBRACKET,
    ']': TT.RBRACKET,
    '+': TT.PLUS,
    '*': TT.STAR,
    '/': TT.SLASH,
    '&': TT.AMP,
    '|': TT.PIPE,
    '.': TT.DOT,
    '#': TT.HASH,
    '?': TT.QUESTION,
    '^': TT.CARET,
    '~': TT.TILDE,
    '\\': TT.BACKSLASH,
}

_TYPE_KWS  = frozenset('iufbsv')
_BOOL_KWS  = frozenset(('T', 'F'))


class LexError(Exception):
    def __init__(self, msg: str, line: int, col: int):
        super().__init__(f"{line}:{col}: {msg}")
        self.line = line
        self.col = col


@dataclass(frozen=True)
class Token:
    type:  TT
    value: str
    line:  int
    col:   int

    def __repr__(self) -> str:
        return f"Token({self.type.name}, {self.value!r}, {self.line}:{self.col})"


class Lexer:
    def __init__(self, source: str, filename: str = "<input>"):
        self.src      = source
        self.pos      = 0
        self.line     = 1
        self.col      = 1
        self.filename = filename

    # ── helpers ──────────────────────────────────────────────────────

    def _peek(self, offset: int = 0) -> str:
        p = self.pos + offset
        return self.src[p] if p < len(self.src) else '\0'

    def _advance(self) -> str:
        ch = self.src[self.pos]
        self.pos += 1
        if ch == '\n':
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return ch

    def _skip(self) -> None:
        """Skip whitespace and // line comments."""
        while self.pos < len(self.src):
            ch = self._peek()
            if ch in ' \t\n\r':
                self._advance()
            elif ch == '/' and self._peek(1) == '/':
                while self.pos < len(self.src) and self._peek() != '\n':
                    self._advance()
            else:
                break

    def _err(self, msg: str) -> LexError:
        return LexError(msg, self.line, self.col)

    # ── public API ───────────────────────────────────────────────────

    def tokenize(self) -> List[Token]:
        """Return all tokens including the final EOF."""
        tokens: List[Token] = []
        while True:
            tok = self._next()
            tokens.append(tok)
            if tok.type == TT.EOF:
                break
        return tokens

    # ── internal: next token ─────────────────────────────────────────

    def _next(self) -> Token:
        self._skip()

        if self.pos >= len(self.src):
            return Token(TT.EOF, '', self.line, self.col)

        ln, cl = self.line, self.col
        ch = self._peek()

        # Unicode arrow  →  (U+2192, encoded as 3 UTF-8 bytes)
        if ch == '→':
            self._advance()
            return Token(TT.ARROW, '→', ln, cl)

        # ASCII arrow ->
        if ch == '-' and self._peek(1) == '>':
            self._advance(); self._advance()
            return Token(TT.ARROW, '->', ln, cl)

        # % (modulo only — no overloading in v0.1)
        if ch == '%':
            self._advance()
            return Token(TT.PERCENT, '%', ln, cl)

        # Multi-char operators that start with =  < > ! -
        if ch == '=':
            if self._peek(1) == '=':
                self._advance(); self._advance()
                return Token(TT.EQ, '==', ln, cl)
            self._advance()
            return Token(TT.ASSIGN, '=', ln, cl)

        if ch == '!':
            if self._peek(1) == '=':
                self._advance(); self._advance()
                return Token(TT.NEQ, '!=', ln, cl)
            self._advance()
            return Token(TT.BANG, '!', ln, cl)

        if ch == '<':
            if self._peek(1) == '=':
                self._advance(); self._advance()
                return Token(TT.LEQ, '<=', ln, cl)
            if self._peek(1) == '<':
                self._advance(); self._advance()
                return Token(TT.SHL, '<<', ln, cl)
            self._advance()
            return Token(TT.LT, '<', ln, cl)

        if ch == '>':
            if self._peek(1) == '=':
                self._advance(); self._advance()
                return Token(TT.GEQ, '>=', ln, cl)
            if self._peek(1) == '>':
                self._advance(); self._advance()
                return Token(TT.SHR, '>>', ln, cl)
            self._advance()
            return Token(TT.GT, '>', ln, cl)

        if ch == '-':
            # Negative numeric literal: '-' immediately followed by a digit
            # (no intervening whitespace). Binary MINUS is written with a
            # space before the operand ( '- a b' ) so there is no ambiguity.
            if self._peek(1).isdigit():
                return self._lex_number(ln, cl)
            self._advance()
            return Token(TT.MINUS, '-', ln, cl)

        # Single-character tokens
        if ch in _SINGLE:
            self._advance()
            return Token(_SINGLE[ch], ch, ln, cl)

        # Backtick string: `content`
        if ch == '`':
            return self._lex_str(ln, cl)

        # Number
        if ch.isdigit():
            return self._lex_number(ln, cl)

        # Identifier / keyword
        if ch.isalpha() or ch == '_':
            return self._lex_ident(ln, cl)

        raise self._err(f"unexpected character {ch!r}")

    # ── sub-lexers ───────────────────────────────────────────────────

    def _lex_str(self, ln: int, cl: int) -> Token:
        self._advance()   # consume opening `
        buf: list[str] = []
        while self.pos < len(self.src):
            c = self._peek()
            if c == '`':
                self._advance()   # consume closing `
                return Token(TT.STR, ''.join(buf), ln, cl)
            # Process \n \t \r \\ escape sequences; other \X pass through
            # unchanged. Mirrors stdlib/runtime.c's backtick lexer.
            if c == '\\' and self.pos + 1 < len(self.src):
                nx = self.src[self.pos + 1]
                if nx == 'n':
                    buf.append('\n'); self.pos += 2; continue
                if nx == 't':
                    buf.append('\t'); self.pos += 2; continue
                if nx == 'r':
                    buf.append('\r'); self.pos += 2; continue
                if nx == '\\':
                    buf.append('\\'); self.pos += 2; continue
            buf.append(self._advance())
        raise LexError("unterminated string literal", ln, cl)

    def _lex_number(self, ln: int, cl: int) -> Token:
        buf: list[str] = []

        def consume_digits() -> None:
            while self.pos < len(self.src) and (self._peek().isdigit() or self._peek() == '_'):
                buf.append(self._advance())

        # Optional leading '-' for negative literals. The caller guarantees
        # it is immediately followed by a digit.
        if self._peek() == '-':
            buf.append(self._advance())

        consume_digits()

        # Float if we see  .  followed by a digit
        if self._peek() == '.' and self._peek(1).isdigit():
            buf.append(self._advance())   # '.'
            consume_digits()
            # Optional exponent
            if self._peek() in ('e', 'E'):
                buf.append(self._advance())
                if self._peek() == '-':
                    buf.append(self._advance())
                consume_digits()
            raw = ''.join(buf).replace('_', '')
            return Token(TT.FLOAT, raw, ln, cl)

        raw = ''.join(buf).replace('_', '')
        return Token(TT.INT, raw, ln, cl)

    def _lex_ident(self, ln: int, cl: int) -> Token:
        buf: list[str] = []
        while self.pos < len(self.src) and (self._peek().isalnum() or self._peek() == '_'):
            buf.append(self._advance())
        name = ''.join(buf)

        # Single-character type keywords are reserved
        if len(name) == 1 and name in _TYPE_KWS:
            return Token(TT.TYPE_KW, name, ln, cl)

        if name in _BOOL_KWS:
            return Token(TT.BOOL, name, ln, cl)

        # Namespace syntax: a::b[::c...] merges into single IDENT with '__'
        # separator so `mod::symbol` becomes `mod__symbol` (name mangling).
        while (self.pos + 2 < len(self.src)
               and self.src[self.pos] == ':' and self.src[self.pos + 1] == ':'
               and (self.src[self.pos + 2].isalpha() or self.src[self.pos + 2] == '_')):
            self._advance(); self._advance()  # consume '::'
            more: list[str] = []
            while self.pos < len(self.src) and (self._peek().isalnum() or self._peek() == '_'):
                more.append(self._advance())
            name = name + '__' + ''.join(more)

        return Token(TT.IDENT, name, ln, cl)
