# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL Parser — recursive descent, LL(1) with bounded lookahead.

Consumes a token list from the Lexer and produces a Program AST.

Grammar summary (see spec/grammar.ebnf for the full spec):

  program     = decl* EOF
  decl        = fn_decl | struct_decl | const_decl | import_decl
  fn_decl     = '@' IDENT param* ARROW type block
  struct_decl = ':' IDENT '{' field* '}'
  const_decl  = ':' type IDENT expr
  import_decl = '$' STR IDENT?

  block  = '{' stmt* '}'
  stmt   = let_stmt | set_stmt | expr
  let_stmt = ':' type? IDENT expr
  set_stmt = '=' IDENT expr

  expr (prefix notation, fixed arity):
    literal | IDENT | call | cond | loop | member | cast | ret |
    unary | binary | block
"""

from __future__ import annotations
from typing import List, Optional
from .lexer import Token, TT, LexError
from .ast_nodes import (
    Pos, Program, Decl, Stmt, Expr, Block, Param,
    NurlType, BaseType, PtrType, SliceType, OptType, FnType, NamedType,
    FnDecl, StructDecl, ConstDecl, ImportDecl,
    FnHeader, TraitDecl, ImplDecl,
    VariantDecl, EnumDecl, EnumConstructor,
    MatchPattern, MatchCase, MatchExpr,
    LetStmt, SetStmt, FieldStoreStmt, ExprStmt,
    IntLit, FloatLit, StrLit, BoolLit, IdentExpr,
    BinExpr, UnExpr, RetExpr, CallExpr, CondExpr,
    LoopExpr, MemberExpr, CastExpr, BlockExpr,
)

_BIN_OPS = {
    TT.PLUS, TT.MINUS, TT.STAR, TT.SLASH, TT.PERCENT,
    TT.LT, TT.GT, TT.EQ, TT.NEQ, TT.LEQ, TT.GEQ,
    TT.SHL, TT.SHR,
    TT.AMP, TT.PIPE,
}

_UNARY_OPS = {TT.BANG, TT.TILDE}

_TYPE_START = {TT.TYPE_KW, TT.STAR, TT.LBRACKET, TT.QUESTION, TT.AT, TT.IDENT, TT.BOOL, TT.LPAREN}


class ParseError(Exception):
    def __init__(self, msg: str, pos: Pos):
        super().__init__(f"{pos}: {msg}")
        self.pos = pos


class Parser:
    def __init__(self, tokens: List[Token], filename: str = "<input>"):
        self.tokens   = tokens
        self.pos      = 0
        self.filename = filename

    # ── helpers ───────────────────────────────────────────────────

    def _peek(self, offset: int = 0) -> Token:
        p = self.pos + offset
        if p < len(self.tokens):
            return self.tokens[p]
        return self.tokens[-1]   # EOF

    def _pos(self, offset: int = 0) -> Pos:
        t = self._peek(offset)
        return Pos(t.line, t.col, self.filename)

    def _advance(self) -> Token:
        t = self.tokens[self.pos]
        if self.pos < len(self.tokens) - 1:
            self.pos += 1
        return t

    def _check(self, *types: TT) -> bool:
        return self._peek().type in types

    def _expect(self, tt: TT, desc: str = '') -> Token:
        t = self._peek()
        if t.type != tt:
            label = desc or tt.name
            raise ParseError(f"expected {label}, got {t.type.name} ({t.value!r})", self._pos())
        return self._advance()

    def _expect_ident(self, desc: str = 'name') -> Token:
        """Accept IDENT or TYPE_KW in name positions (e.g. function name, param name).
        TYPE_KW is allowed as a name so that `f`, `i`, etc. can be used as names
        when context makes it unambiguous (after @, after type in param, etc.).
        """
        t = self._peek()
        if t.type in (TT.IDENT, TT.TYPE_KW):
            return self._advance()
        raise ParseError(f"expected {desc}, got {t.type.name} ({t.value!r})", self._pos())

    def _match(self, *types: TT) -> Optional[Token]:
        if self._peek().type in types:
            return self._advance()
        return None

    def _err(self, msg: str) -> ParseError:
        return ParseError(msg, self._pos())

    # ── public entry point ────────────────────────────────────────

    def parse(self) -> Program:
        decls: List[Decl] = []
        while not self._check(TT.EOF):
            decls.append(self._parse_decl())
        return Program(decls, self.filename)

    # ── declarations ──────────────────────────────────────────────

    def _parse_decl(self) -> Decl:
        t = self._peek()
        if t.type == TT.AT:
            return self._parse_fn_decl()
        if t.type == TT.COLON:
            return self._parse_colon_decl()
        if t.type == TT.DOLLAR:
            return self._parse_import_decl()
        if t.type == TT.PERCENT:
            return self._parse_trait_or_impl()
        if t.type == TT.PIPE:
            return self._parse_enum_decl()
        raise self._err(f"expected declaration (@, :, $, %, |), got {t.type.name} ({t.value!r})")

    def _is_generic_type_params(self) -> bool:
        """
        Look ahead to determine if '[' starts generic type params or a slice parameter.

        Generic type params: [T U V] - simple identifiers followed by ]
        Slice parameter: [Type param_name → - type followed by ident and →

        Returns True if it looks like generic type params, False for slice parameter.
        """
        if not self._check(TT.LBRACKET):
            return False

        # Look ahead from current position (should be on '[')
        i = 1  # Start after '['

        # Scan through potential type parameters
        while True:
            lookahead = self._peek(i)

            # If we hit EOF, assume generic params (incomplete but consistent)
            if lookahead.type == TT.EOF:
                return True

            # If we see ']', it's definitely generic type params
            if lookahead.type == TT.RBRACKET:
                return True

            # If we see '→', it's definitely a slice parameter
            if lookahead.type == TT.ARROW:
                return False

            # If we see simple identifier/type tokens, continue scanning
            if lookahead.type in (TT.IDENT, TT.TYPE_KW, TT.BOOL):
                i += 1
                continue

            # If we see complex type tokens (*, [, ?, @, etc.), it's likely a slice parameter
            if lookahead.type in (TT.STAR, TT.LBRACKET, TT.QUESTION, TT.AT, TT.LPAREN):
                return False

            # Anything else, assume slice parameter to be safe
            return False

    def _parse_fn_decl(self) -> FnDecl:
        pos = self._pos()
        self._expect(TT.AT, '@')
        name = self._expect_ident('function name').value
        # Optional generic type parameters: [T], [K V], etc.
        # Note: T and F lex as BOOL (true/false literals), so we must accept BOOL here.
        type_params: List[str] = []
        if self._check(TT.LBRACKET) and self._is_generic_type_params():
            self._advance()  # consume '['
            while not self._check(TT.RBRACKET, TT.EOF):
                t = self._peek()
                if t.type in (TT.IDENT, TT.TYPE_KW, TT.BOOL):
                    type_params.append(t.value)
                    self._advance()
                else:
                    raise self._err(f'expected type parameter, got {t.type.name} ({t.value!r})')
            self._expect(TT.RBRACKET, ']')
        params: List[Param] = []
        while self._peek().type in _TYPE_START and not self._check(TT.ARROW):
            params.append(self._parse_param())
        self._expect(TT.ARROW, '→')
        ret = self._parse_type()
        body = self._parse_block()
        return FnDecl(name, params, ret, body, pos, type_params)

    def _parse_param(self) -> Param:
        pos = self._pos()
        typ = self._parse_type()
        name = self._expect_ident('parameter name').value
        return Param(typ, name, pos)

    def _parse_colon_decl(self) -> Decl:
        """
        Disambiguate struct_decl vs enum_decl vs const_decl:
          : IDENT '{'     ...  → struct_decl
          : | IDENT '{'   ...  → enum_decl
          : type IDENT    ...  → const_decl
        """
        pos = self._pos()
        self._expect(TT.COLON, ':')

        # Peek: if next is IDENT (not a type keyword) followed by '{' → struct
        if self._peek().type == TT.IDENT and self._peek(1).type == TT.LBRACE:
            return self._parse_struct_body(pos)

        # Peek: if next is | followed by IDENT and '{' → enum
        if self._peek().type == TT.PIPE and self._peek(1).type == TT.IDENT and self._peek(2).type == TT.LBRACE:
            return self._parse_enum_body(pos)

        # Otherwise: parse type, then name, then expr → const
        typ = self._parse_type()
        name = self._expect(TT.IDENT, 'constant name').value
        expr = self._parse_expr()
        return ConstDecl(typ, name, expr, pos)

    def _parse_struct_body(self, pos: Pos) -> StructDecl:
        name = self._expect(TT.IDENT, 'struct name').value
        self._expect(TT.LBRACE, '{')
        fields: List[Param] = []
        while not self._check(TT.RBRACE, TT.EOF):
            fields.append(self._parse_param())
        self._expect(TT.RBRACE, '}')
        return StructDecl(name, fields, pos)

    def _parse_import_decl(self) -> ImportDecl:
        pos = self._pos()
        self._expect(TT.DOLLAR, '$')
        path = self._expect(TT.STR, 'import path').value
        alias: Optional[str] = None
        if self._check(TT.IDENT):
            alias = self._advance().value
        return ImportDecl(path, alias, pos)

    def _parse_enum_decl(self) -> EnumDecl:
        """Parse | EnumName { variant* } where variant is VariantName type*"""
        pos = self._pos()
        self._expect(TT.PIPE, '|')
        name = self._expect_ident('enum name').value
        self._expect(TT.LBRACE, '{')
        variants: List[VariantDecl] = []
        while not self._check(TT.RBRACE, TT.EOF):
            variants.append(self._parse_variant())
        self._expect(TT.RBRACE, '}')
        return EnumDecl(name, variants, pos)

    def _parse_enum_body(self, pos: Pos) -> EnumDecl:
        """Parse | EnumName { variant* } after : has been consumed"""
        self._expect(TT.PIPE, '|')
        name = self._expect_ident('enum name').value
        self._expect(TT.LBRACE, '{')
        variants: List[VariantDecl] = []
        while not self._check(TT.RBRACE, TT.EOF):
            variants.append(self._parse_variant())
        self._expect(TT.RBRACE, '}')
        return EnumDecl(name, variants, pos)

    def _parse_variant(self) -> VariantDecl:
        """Parse VariantName type*"""
        pos = self._pos()
        variant_name = self._expect_ident('variant name').value
        payload: List[NurlType] = []
        # Parse payload types on the same line only
        while (self._check(TT.TYPE_KW) and  # Only parse base types for now
               not self._check(TT.RBRACE)):
            payload.append(self._parse_type())
        return VariantDecl(variant_name, payload, pos)

    def _parse_trait_or_impl(self) -> Decl:
        """Parse % Name type_params? '{' headers '}' (trait) or % Name type_params? type '{' fns '}' (impl)."""
        pos = self._pos()
        self._expect(TT.PERCENT, '%')
        name = self._expect_ident('trait name').value
        # Optional type params [T V ...]
        type_params: List[str] = []
        if self._check(TT.LBRACKET):
            self._advance()
            while not self._check(TT.RBRACKET, TT.EOF):
                t = self._peek()
                if t.type in (TT.IDENT, TT.TYPE_KW, TT.BOOL):
                    type_params.append(t.value)
                    self._advance()
                else:
                    raise self._err(f'expected type parameter, got {t.type.name}')
            self._expect(TT.RBRACKET, ']')
        # Disambiguate: '{' → trait_decl, else → impl_decl
        if self._check(TT.LBRACE):
            # trait_decl: parse method signatures (no bodies)
            self._advance()  # consume '{'
            methods: List[FnHeader] = []
            while not self._check(TT.RBRACE, TT.EOF):
                if self._check(TT.AT):
                    methods.append(self._parse_fn_header())
                else:
                    self._advance()
            self._expect(TT.RBRACE, '}')
            return TraitDecl(name, type_params, methods, pos)
        else:
            # impl_decl: parse implementing type then method bodies
            impl_type = self._parse_type()
            self._expect(TT.LBRACE, '{')
            fns: List[FnDecl] = []
            while not self._check(TT.RBRACE, TT.EOF):
                if self._check(TT.AT):
                    fns.append(self._parse_fn_decl())
                else:
                    self._advance()
            self._expect(TT.RBRACE, '}')
            return ImplDecl(name, type_params, impl_type, fns, pos)

    def _parse_fn_header(self) -> FnHeader:
        """Parse @ name param* → ret (no body — for trait method signatures)."""
        pos = self._pos()
        self._expect(TT.AT, '@')
        name = self._expect_ident('method name').value
        params: List[Param] = []
        while self._peek().type in _TYPE_START and not self._check(TT.ARROW):
            params.append(self._parse_param())
        self._expect(TT.ARROW, '→')
        ret = self._parse_type()
        return FnHeader(name, params, ret, pos)

    # ── types ─────────────────────────────────────────────────────

    def _parse_type(self) -> NurlType:
        t = self._peek()

        if t.type == TT.TYPE_KW:
            self._advance()
            return BaseType(t.value)

        if t.type == TT.STAR:
            self._advance()
            return PtrType(self._parse_type())

        if t.type == TT.LBRACKET:
            self._advance()
            return SliceType(self._parse_type())

        if t.type == TT.QUESTION:
            self._advance()
            return OptType(self._parse_type())

        if t.type == TT.AT:
            self._advance()
            ret = self._parse_type()
            params: List[NurlType] = []
            while self._peek().type in _TYPE_START:
                params.append(self._parse_type())
            return FnType(ret, params)

        if t.type == TT.LPAREN:
            self._advance()  # consume '('
            inner_type = self._parse_type()
            self._expect(TT.RPAREN, ')')
            return inner_type

        if t.type == TT.IDENT:
            self._advance()
            return NamedType(t.value)

        # BOOL tokens (T, F) used as type variable names in generics
        if t.type == TT.BOOL:
            self._advance()
            return NamedType(t.value)

        raise ParseError(f"expected type, got {t.type.name} ({t.value!r})", self._pos())

    # ── block ──────────────────────────────────────────────────────

    def _parse_block(self) -> Block:
        pos = self._pos()
        self._expect(TT.LBRACE, '{')
        stmts: List[Stmt] = []
        while not self._check(TT.RBRACE, TT.EOF):
            stmts.append(self._parse_stmt())
        self._expect(TT.RBRACE, '}')
        return Block(stmts, pos)

    # ── statements ────────────────────────────────────────────────

    def _parse_stmt(self) -> Stmt:
        t = self._peek()

        # Let: : type? name expr
        if t.type == TT.COLON:
            return self._parse_let_stmt()

        # Set: = name expr
        if t.type == TT.ASSIGN:
            return self._parse_set_stmt()

        # Expression statement
        expr = self._parse_expr()
        return ExprStmt(expr, expr.pos)

    def _parse_let_stmt(self) -> LetStmt:
        pos = self._pos()
        self._expect(TT.COLON, ':')

        # Optional '~' marks the binding as mutable. The bootstrap doesn't
        # enforce mutability; it just consumes the token so that code
        # written in the self-hosted compiler's style — `: ~ i idx 0` — is
        # accepted here too.
        if self._peek().type == TT.TILDE:
            self._advance()

        # Determine if there's an explicit type.
        # Heuristic: if current token is a type-start token, and it's not
        # the ONLY token before another token that would be an expr-start,
        # try parsing a type.
        #
        # Disambiguation:
        #   : i n 0     → type=i, name=n, expr=0
        #   : n 0       → type=None, name=n, expr=0  (type inferred)
        #
        # If the token after ':' is a TYPE_KW or compound type sigil (* [ ?),
        # parse it as a type.  If it's an IDENT, it could be either the name
        # (no explicit type) or a NamedType.  We check the token after it:
        #   IDENT IDENT → first is NamedType, second is name
        #   IDENT <expr_start> → first is name, no type

        typ: Optional[NurlType] = None

        if self._peek().type in (TT.TYPE_KW, TT.STAR, TT.LBRACKET, TT.QUESTION, TT.AT, TT.LPAREN):
            typ = self._parse_type()
        elif self._peek().type == TT.IDENT and self._peek(1).type == TT.IDENT:
            # NamedType followed by variable name
            typ = NamedType(self._advance().value)

        name = self._expect_ident('binding name').value
        expr = self._parse_expr()
        return LetStmt(typ, name, expr, pos)

    def _parse_set_stmt(self) -> Stmt:
        pos = self._pos()
        self._expect(TT.ASSIGN, '=')
        if self._peek().type == TT.DOT:
            self._advance()  # consume '.'
            obj   = self._parse_expr()
            field = self._expect_ident('field name').value
            rhs   = self._parse_expr()
            return FieldStoreStmt(obj, field, rhs, pos)
        name = self._expect_ident('variable name').value
        expr = self._parse_expr()
        return SetStmt(name, expr, pos)

    # ── expressions ───────────────────────────────────────────────
    #
    # All expressions are in PREFIX notation.
    # The first token determines which expression rule applies.

    def _parse_expr(self) -> Expr:
        t = self._peek()

        # Literals
        if t.type == TT.INT:
            self._advance()
            return IntLit(int(t.value), Pos(t.line, t.col, self.filename))

        if t.type == TT.FLOAT:
            self._advance()
            return FloatLit(float(t.value), Pos(t.line, t.col, self.filename))

        if t.type == TT.STR:
            self._advance()
            return StrLit(t.value, Pos(t.line, t.col, self.filename))

        if t.type == TT.BOOL:
            self._advance()
            return BoolLit(t.value == 'T', Pos(t.line, t.col, self.filename))

        # Identifier (TYPE_KW allowed as variable name in expression position,
        # e.g. a parameter named 'v', 's', 'i', etc.)
        if t.type in (TT.IDENT, TT.TYPE_KW):
            self._advance()
            return IdentExpr(t.value, Pos(t.line, t.col, self.filename))

        # Block expression  { stmt* }
        if t.type == TT.LBRACE:
            pos = self._pos()
            blk = self._parse_block()
            return BlockExpr(blk.stmts, pos)

        # Function call  ( fn arg* )
        if t.type == TT.LPAREN:
            return self._parse_call()

        # Enum constructor  @ EnumName { VariantName arg* }
        if t.type == TT.AT:
            return self._parse_enum_constructor()

        # Match expression  ?? expr { pattern → result ... }
        # or Conditional   ? cond then else
        if t.type == TT.QUESTION:
            if self._peek(1).type == TT.QUESTION:  # ??
                return self._parse_match()
            else:
                return self._parse_cond()

        # Tilde: loop  ~ cond { body }
        #        or bitnot/negate  ~ expr
        if t.type == TT.TILDE:
            return self._parse_tilde()

        # Return  ^ expr
        if t.type == TT.CARET:
            pos = self._pos()
            self._advance()
            expr = self._parse_expr()
            return RetExpr(expr, pos)

        # Logical not  ! expr
        if t.type == TT.BANG:
            pos = self._pos()
            self._advance()
            expr = self._parse_expr()
            return UnExpr('!', expr, pos)

        # Member access  . obj field
        if t.type == TT.DOT:
            return self._parse_member()

        # Cast  # type expr
        if t.type == TT.HASH:
            return self._parse_cast()

        # Binary operators  OP left right
        if t.type in _BIN_OPS:
            return self._parse_binary()

        raise ParseError(
            f"expected expression, got {t.type.name} ({t.value!r})",
            Pos(t.line, t.col, self.filename),
        )

    # ── expression sub-parsers ────────────────────────────────────

    def _parse_call(self) -> CallExpr:
        pos = self._pos()
        self._expect(TT.LPAREN, '(')
        fn = self._parse_expr()
        # Optional generic type arguments: [i], [s T], etc.
        type_args: List[str] = []
        if self._check(TT.LBRACKET):
            self._advance()  # consume '['
            while not self._check(TT.RBRACKET, TT.EOF):
                t = self._peek()
                if t.type in (TT.TYPE_KW, TT.IDENT):
                    type_args.append(t.value)
                    self._advance()
                else:
                    break
            self._expect(TT.RBRACKET, ']')
        args: List[Expr] = []
        while not self._check(TT.RPAREN, TT.EOF):
            args.append(self._parse_expr())
        self._expect(TT.RPAREN, ')')
        return CallExpr(fn, args, pos, type_args)

    def _parse_cond(self) -> CondExpr:
        pos = self._pos()
        self._expect(TT.QUESTION, '?')
        cond  = self._parse_expr()
        then  = self._parse_expr()
        else_ = self._parse_expr()
        return CondExpr(cond, then, else_, pos)

    def _parse_match(self) -> MatchExpr:
        """Parse ?? expr { pattern → result ... }"""
        pos = self._pos()
        self._expect(TT.QUESTION, '?')  # First ?
        self._expect(TT.QUESTION, '?')  # Second ?
        expr = self._parse_expr()
        self._expect(TT.LBRACE, '{')
        cases: List[MatchCase] = []
        while not self._check(TT.RBRACE, TT.EOF):
            cases.append(self._parse_match_case())
        self._expect(TT.RBRACE, '}')
        return MatchExpr(expr, cases, pos)

    def _parse_match_case(self) -> MatchCase:
        """Parse pattern → result"""
        pos = self._pos()
        pattern = self._parse_match_pattern()
        self._expect(TT.ARROW, '→')
        result = self._parse_expr()
        return MatchCase(pattern, result, pos)

    def _parse_match_pattern(self) -> MatchPattern:
        """Parse VariantName var1 var2 ... or just VariantName"""
        pos = self._pos()
        variant_name = self._expect_ident('variant name').value
        variables: List[str] = []
        # Parse variable names for payload binding
        while self._check(TT.IDENT, TT.TYPE_KW) and not self._check(TT.ARROW):
            var_name = self._expect_ident('variable name').value
            variables.append(var_name)
        return MatchPattern(variant_name, variables, pos)

    def _parse_enum_constructor(self) -> EnumConstructor:
        """Parse @ EnumName { VariantName arg* }"""
        pos = self._pos()
        self._expect(TT.AT, '@')
        enum_name = self._expect_ident('enum name').value
        self._expect(TT.LBRACE, '{')
        variant_name = self._expect_ident('variant name').value
        args: List[Expr] = []
        while not self._check(TT.RBRACE, TT.EOF):
            args.append(self._parse_expr())
        self._expect(TT.RBRACE, '}')
        return EnumConstructor(enum_name, variant_name, args, pos)

    def _parse_tilde(self) -> Expr:
        """
        ~ cond { body }   → LoopExpr
        ~ expr            → UnExpr('~', expr)  bitnot/negate

        We parse the condition/operand first, then peek.
        If next token is '{', it's a loop; otherwise it's unary.
        """
        pos = self._pos()
        self._expect(TT.TILDE, '~')
        operand = self._parse_expr()
        if self._check(TT.LBRACE):
            body = self._parse_block()
            return LoopExpr(operand, body, pos)
        return UnExpr('~', operand, pos)

    def _parse_member(self) -> MemberExpr:
        pos = self._pos()
        self._expect(TT.DOT, '.')
        obj   = self._parse_expr()
        field = self._expect(TT.IDENT, 'field name').value
        return MemberExpr(obj, field, pos)

    def _parse_cast(self) -> CastExpr:
        pos = self._pos()
        self._expect(TT.HASH, '#')
        typ  = self._parse_type()
        expr = self._parse_expr()
        return CastExpr(typ, expr, pos)

    def _parse_binary(self) -> BinExpr:
        t = self._peek()
        pos = self._pos()
        self._advance()
        left  = self._parse_expr()
        right = self._parse_expr()
        return BinExpr(t.value, left, right, pos)


# ── convenience function ──────────────────────────────────────────

def parse(source: str, filename: str = "<input>") -> Program:
    from .lexer import Lexer
    tokens = Lexer(source, filename).tokenize()
    return Parser(tokens, filename).parse()
