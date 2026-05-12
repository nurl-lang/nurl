# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL AST node definitions.

All nodes carry a Pos for error reporting.
Types and expressions are kept in separate hierarchies.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, List, Union


# ── Source position ────────────────────────────────────────────────

@dataclass(frozen=True)
class Pos:
    line: int
    col:  int
    file: str = "<input>"

    def __str__(self) -> str:
        return f"{self.file}:{self.line}:{self.col}"


# ── Type nodes ────────────────────────────────────────────────────
#
# These mirror the type grammar:
#   base_type  ::= i | u | f | b | s | v
#   ptr_type   ::= * type
#   slice_type ::= [ type
#   opt_type   ::= ? type
#   fn_type    ::= @ ret param*
#   named_type ::= IDENT

class NurlType:
    """Base class for all type AST nodes."""
    pass


@dataclass
class BaseType(NurlType):
    """Primitive type: i u f b s v."""
    name: str        # single char

    def __str__(self) -> str:
        return self.name


@dataclass
class PtrType(NurlType):
    """Owned pointer: *T."""
    inner: NurlType

    def __str__(self) -> str:
        return f"*{self.inner}"


@dataclass
class SliceType(NurlType):
    """Contiguous slice: [T."""
    inner: NurlType

    def __str__(self) -> str:
        return f"[{self.inner}"


@dataclass
class OptType(NurlType):
    """Option: ?T."""
    inner: NurlType

    def __str__(self) -> str:
        return f"?{self.inner}"


@dataclass
class FnType(NurlType):
    """Function type: @ret param1 param2 ..."""
    ret:    NurlType
    params: List[NurlType]

    def __str__(self) -> str:
        ps = ' '.join(str(p) for p in self.params)
        return f"@{self.ret} {ps}".rstrip()


@dataclass
class NamedType(NurlType):
    """User-defined struct or type alias."""
    name: str

    def __str__(self) -> str:
        return self.name


# ── Expression nodes ──────────────────────────────────────────────

class Expr:
    """Base class for all expression AST nodes."""
    # Filled in by the type-checker; None until then.
    nurl_type: Optional[NurlType] = field(default=None, init=False, repr=False)


@dataclass
class IntLit(Expr):
    value: int
    pos:   Pos


@dataclass
class FloatLit(Expr):
    value: float
    pos:   Pos


@dataclass
class StrLit(Expr):
    value: str
    pos:   Pos


@dataclass
class BoolLit(Expr):
    value: bool
    pos:   Pos


@dataclass
class IdentExpr(Expr):
    name: str
    pos:  Pos


@dataclass
class BinExpr(Expr):
    """Binary operation: OP left right  (prefix notation)."""
    op:    str        # + - * / % < > == != <= >= & |
    left:  Expr
    right: Expr
    pos:   Pos


@dataclass
class UnExpr(Expr):
    """Unary operation: OP expr  (prefix notation)."""
    op:   str         # ! or ~
    expr: Expr
    pos:  Pos


@dataclass
class RetExpr(Expr):
    """Return: ^ expr."""
    expr: Expr
    pos:  Pos


@dataclass
class CallExpr(Expr):
    """Function call: ( fn [type_args]? arg* )."""
    fn:        Expr
    args:      List[Expr]
    pos:       Pos
    type_args: List[str] = field(default_factory=list)


@dataclass
class CondExpr(Expr):
    """Conditional: ? cond then else."""
    cond:  Expr
    then:  Expr
    else_: Expr
    pos:   Pos


@dataclass
class LoopExpr(Expr):
    """While loop: ~ cond { body }."""
    cond: Expr
    body: Block
    pos:  Pos


@dataclass
class MemberExpr(Expr):
    """Member access: . obj field."""
    obj:   Expr
    field: str
    pos:   Pos


@dataclass
class CastExpr(Expr):
    """Type cast: # type expr."""
    target: NurlType
    expr:   Expr
    pos:    Pos


@dataclass
class BlockExpr(Expr):
    """Block used as expression: { stmt* }."""
    stmts: List['Stmt']
    pos:   Pos


# ── Statement nodes ───────────────────────────────────────────────

class Stmt:
    """Base class for all statement AST nodes."""
    pass


@dataclass
class LetStmt(Stmt):
    """Bind a new name: : type? name expr."""
    type: Optional[NurlType]
    name: str
    expr: Expr
    pos:  Pos


@dataclass
class SetStmt(Stmt):
    """Assign to existing binding: = name expr."""
    name: str
    expr: Expr
    pos:  Pos


@dataclass
class FieldStoreStmt(Stmt):
    """Field store through pointer: = . obj field rhs."""
    obj:   Expr
    field: str
    rhs:   Expr
    pos:   Pos


@dataclass
class ExprStmt(Stmt):
    """Expression evaluated for side-effects."""
    expr: Expr
    pos:  Pos


# ── Block ─────────────────────────────────────────────────────────

@dataclass
class Block:
    """{ stmt* }"""
    stmts: List[Stmt]
    pos:   Pos


# ── Declaration nodes ─────────────────────────────────────────────

class Decl:
    """Base class for top-level declarations."""
    pass


@dataclass
class Param:
    """A function parameter or struct field: type name."""
    type: NurlType
    name: str
    pos:  Pos


@dataclass
class FnDecl(Decl):
    """@ name [type_params]? param* → ret { body }."""
    name:        str
    params:      List[Param]
    ret_type:    NurlType
    body:        Block
    pos:         Pos
    type_params: List[str] = field(default_factory=list)


@dataclass
class StructDecl(Decl):
    """
    : name { field* }

    where each field is  type name.
    """
    name:   str
    fields: List[Param]
    pos:    Pos


@dataclass
class ConstDecl(Decl):
    """: type name expr  (when the token after name is NOT '{')."""
    type: NurlType
    name: str
    expr: Expr
    pos:  Pos


@dataclass
class ImportDecl(Decl):
    """$ `path` alias?"""
    path:  str
    alias: Optional[str]
    pos:   Pos


@dataclass
class FnHeader:
    """Method signature (no body) for trait declarations: @ name param* → ret."""
    name:     str
    params:   List[Param]
    ret_type: NurlType
    pos:      Pos


@dataclass
class TraitDecl(Decl):
    """% Name type_params? { fn_header* }"""
    name:        str
    type_params: List[str]
    methods:     List[FnHeader]
    pos:         Pos


@dataclass
class ImplDecl(Decl):
    """% TraitName type_params? type { fn_decl* }"""
    trait_name:  str
    type_params: List[str]
    impl_type:   NurlType
    methods:     List[FnDecl]
    pos:         Pos


@dataclass
class VariantDecl:
    """A single variant within an enum: VariantName type*"""
    name:    str
    payload: List[NurlType]  # Empty for unit variants like Close
    pos:     Pos


@dataclass
class EnumDecl(Decl):
    """| EnumName { variant* }"""
    name:     str
    variants: List[VariantDecl]
    pos:      Pos


# ── Enum constructor expression ───────────────────────────────────

@dataclass
class EnumConstructor(Expr):
    """Enum constructor: @ EnumName { VariantName arg* }"""
    enum_name:    str
    variant_name: str
    args:         List[Expr]
    pos:          Pos


# ── Pattern matching ──────────────────────────────────────────────

@dataclass
class MatchPattern:
    """Pattern in match expression: VariantName var*"""
    variant_name: str
    variables:    List[str]  # Variable names to bind payload to
    pos:          Pos


@dataclass
class MatchCase:
    """Single case in match: pattern → expr"""
    pattern: MatchPattern
    result:  Expr
    pos:     Pos


@dataclass
class MatchExpr(Expr):
    """Pattern matching: ?? expr { case* }"""
    expr:  Expr
    cases: List[MatchCase]
    pos:   Pos


# ── Program ───────────────────────────────────────────────────────

@dataclass
class Program:
    decls: List[Decl]
    file:  str = "<input>"
