# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL Type Checker — annotates the AST with resolved types.

Implements:
  - Symbol table (scoped environment)
  - Bidirectional type inference (simple: infer literals, check bindings)
  - Type equality checking (no implicit conversions)
  - Return type validation

Does NOT implement (v0.1):
  - Hindley-Milner unification (generics come in v0.2)
  - Borrow checker (tracked separately)
  - Sum type exhaustiveness
"""

from __future__ import annotations
from typing import Dict, Optional, List
from .ast_nodes import (
    Program, Decl, Stmt, Expr, Block, Param, NurlType,
    BaseType, PtrType, SliceType, OptType, FnType, NamedType,
    FnDecl, StructDecl, ConstDecl, ImportDecl,
    FnHeader, TraitDecl, ImplDecl,
    VariantDecl, EnumDecl, EnumConstructor,
    MatchPattern, MatchCase, MatchExpr,
    LetStmt, SetStmt, FieldStoreStmt, ExprStmt,
    IntLit, FloatLit, StrLit, BoolLit, IdentExpr,
    BinExpr, UnExpr, RetExpr, CallExpr, CondExpr,
    LoopExpr, MemberExpr, CastExpr, BlockExpr,
    Pos,
)

# ── Built-in types (singletons) ────────────────────────────────────

TI = BaseType('i')
TU = BaseType('u')
TF = BaseType('f')
TB = BaseType('b')
TS = BaseType('s')
TV = BaseType('v')

_BASE = {'i': TI, 'u': TU, 'f': TF, 'b': TB, 's': TS, 'v': TV}

# ── Built-in stdlib functions (callable without import) ────────────
#
# These map to C symbols in stdlib/runtime.c.
# LLVM name = 'nurl_' + NURL name  (see llvm_gen._BUILTIN_LLVM_NAMES).

_BUILTINS: Dict[str, FnType] = {
    # ── User-facing I/O (both nurl_ prefix and bare forms) ──
    'print_int':       FnType(ret=TV, params=[TI]),
    'print_str':       FnType(ret=TV, params=[TS]),
    'print_bool':      FnType(ret=TV, params=[TB]),
    'read_int':        FnType(ret=TI, params=[]),
    'nurl_print_int':  FnType(ret=TV, params=[TI]),
    'nurl_print_str':  FnType(ret=TV, params=[TS]),
    'nurl_print_bool': FnType(ret=TV, params=[TB]),
    'nurl_read_int':   FnType(ret=TI, params=[]),

    # ── String operations ──
    'nurl_print':      FnType(ret=TV, params=[TS]),
    'nurl_eprint':     FnType(ret=TV, params=[TS]),
    'nurl_eprintln':   FnType(ret=TV, params=[TS]),
    'nurl_str_len':    FnType(ret=TI, params=[TS]),
    'nurl_str_get':    FnType(ret=TI, params=[TS, TI]),
    'nurl_str_eq':     FnType(ret=TI, params=[TS, TS]),
    'nurl_str_cmp':    FnType(ret=TI, params=[TS, TS]),
    'nurl_str_cat':    FnType(ret=TS, params=[TS, TS]),
    'nurl_str_cat3':   FnType(ret=TS, params=[TS, TS, TS]),
    'nurl_str_cat4':   FnType(ret=TS, params=[TS, TS, TS, TS]),
    'nurl_str_int':    FnType(ret=TS, params=[TI]),
    'nurl_str_to_int': FnType(ret=TI, params=[TS]),
    'nurl_str_to_float': FnType(ret=TF, params=[TS]),
    'nurl_str_slice':  FnType(ret=TS, params=[TS, TI, TI]),
    'nurl_str_starts': FnType(ret=TI, params=[TS, TS]),
    'nurl_str_find':   FnType(ret=TI, params=[TS, TS]),
    'nurl_str_float':  FnType(ret=TS, params=[TF]),

    # Char classification (formerly nurl_is_alpha / _digit / _space /
    # _alnum_) moved to pure-NURL `stdlib/core/char.nu` as PURIFY.md
    # Phase 1 (2026-05-23); no FFI symbols here anymore.

    # ── File & process ──
    'nurl_read_file':  FnType(ret=TS, params=[TS]),
    'nurl_read_n_bytes': FnType(ret=TS, params=[TI]),
    'nurl_exit':       FnType(ret=TV, params=[TI]),
    'nurl_argc':       FnType(ret=TI, params=[]),
    'nurl_argv':       FnType(ret=TS, params=[TI]),

    # ── Lexer (opaque handle = i) ──
    'nurl_lex_new':       FnType(ret=TI, params=[TS, TS]),
    'nurl_lex_type':      FnType(ret=TI, params=[TI]),
    'nurl_lex_val':       FnType(ret=TS, params=[TI]),
    'nurl_lex_inum':      FnType(ret=TI, params=[TI]),
    'nurl_lex_advance':   FnType(ret=TV, params=[TI]),
    'nurl_lex_peek_type': FnType(ret=TI, params=[TI]),
    'nurl_lex_peek2_type':FnType(ret=TI, params=[TI]),
    'nurl_lex_peek3_type':FnType(ret=TI, params=[TI]),
    'nurl_lex_peek4_type':FnType(ret=TI, params=[TI]),
    'nurl_lex_line':       FnType(ret=TI, params=[TI]),
    'nurl_lex_col':        FnType(ret=TI, params=[TI]),
    'nurl_lex_line_text':  FnType(ret=TS, params=[TI]),
    'nurl_diag_caret':     FnType(ret=TS, params=[TI]),
    'nurl_lex_filename':   FnType(ret=TS, params=[TI]),
    'nurl_lex_cur_start':  FnType(ret=TI, params=[TI]),
    'nurl_lex_src_slice':  FnType(ret=TS, params=[TI, TI, TI]),
    'nurl_lex_set_pos':    FnType(ret=TV, params=[TI, TI]),
    'nurl_print_buf_start':FnType(ret=TV, params=[]),
    'nurl_print_buf_stop': FnType(ret=TS, params=[]),
    'nurl_print_buf_reset':FnType(ret=TV, params=[]),
    'nurl_argv_count':     FnType(ret=TI, params=[]),
    'nurl_argv_get':       FnType(ret=TS, params=[TI]),

    # ── Symbol table (opaque handle = i) ──
    'nurl_sym_new':  FnType(ret=TI, params=[]),
    'nurl_sym_def':  FnType(ret=TV, params=[TI, TS, TS]),
    'nurl_sym_get':  FnType(ret=TS, params=[TI, TS]),
    'nurl_sym_push': FnType(ret=TV, params=[TI]),
    'nurl_sym_pop':  FnType(ret=TV, params=[TI]),

    # ── Codegen helpers (opaque handle = i) ──
    'nurl_cg_new':   FnType(ret=TI, params=[]),
    'nurl_cg_reg':   FnType(ret=TS, params=[TI]),
    'nurl_cg_lbl':   FnType(ret=TS, params=[TI, TS]),
    'nurl_cg_reset': FnType(ret=TV, params=[TI]),

    # ── Type sideband ──
    'nurl_get_last_type': FnType(ret=TS, params=[]),
    'nurl_set_last_type': FnType(ret=TV, params=[TS]),

    # ── Memory allocation ──
    'nurl_malloc': FnType(ret=PtrType(BaseType('v')), params=[TI]),
    'nurl_free':   FnType(ret=TV, params=[PtrType(BaseType('v'))]),

    # ── String Builder (opaque handle = *v) ──
    'nurl_sb_new':       FnType(ret=PtrType(BaseType('v')), params=[]),
    'nurl_sb_str':       FnType(ret=TS, params=[PtrType(BaseType('v'))]),
    'nurl_sb_len':       FnType(ret=TI, params=[PtrType(BaseType('v'))]),
    'nurl_sb_add':       FnType(ret=TV, params=[PtrType(BaseType('v')), TS]),
    'nurl_sb_add_int':   FnType(ret=TV, params=[PtrType(BaseType('v')), TI]),
    'nurl_sb_add_float': FnType(ret=TV, params=[PtrType(BaseType('v')), TF]),
    'nurl_sb_clear':     FnType(ret=TV, params=[PtrType(BaseType('v'))]),
    'nurl_sb_free':      FnType(ret=TV, params=[PtrType(BaseType('v'))]),

    # ── File I/O ──
    'nurl_file_open':   FnType(ret=PtrType(BaseType('v')), params=[TS, TS]),
    'nurl_file_write':  FnType(ret=TV, params=[PtrType(BaseType('v')), TS]),
    'nurl_file_close':  FnType(ret=TV, params=[PtrType(BaseType('v'))]),
    'nurl_file_read':   FnType(ret=TS, params=[TS]),
    'nurl_file_exists': FnType(ret=TI, params=[TS]),
    'nurl_file_size':   FnType(ret=TI, params=[TS]),
    'nurl_file_del':    FnType(ret=TV, params=[TS]),
}


# ── Generic type substitution ──────────────────────────────────────

def _subst_type(t: NurlType, type_map: Dict[str, NurlType]) -> NurlType:
    """Substitute type variables in t according to type_map."""
    if isinstance(t, NamedType) and t.name in type_map:
        return type_map[t.name]
    if isinstance(t, PtrType):
        return PtrType(_subst_type(t.inner, type_map))
    if isinstance(t, SliceType):
        return SliceType(_subst_type(t.inner, type_map))
    if isinstance(t, OptType):
        return OptType(_subst_type(t.inner, type_map))
    return t


# ── Type utilities ─────────────────────────────────────────────────

def types_equal(a: NurlType, b: NurlType) -> bool:
    if type(a) != type(b):
        return False
    if isinstance(a, BaseType):
        return a.name == b.name
    if isinstance(a, (PtrType, SliceType, OptType)):
        return types_equal(a.inner, b.inner)
    if isinstance(a, FnType):
        return (types_equal(a.ret, b.ret)
                and len(a.params) == len(b.params)
                and all(types_equal(p, q) for p, q in zip(a.params, b.params)))
    if isinstance(a, NamedType):
        return a.name == b.name
    return False


def type_str(t: NurlType) -> str:
    return str(t)


# ── Error ──────────────────────────────────────────────────────────

class TypeError(Exception):
    def __init__(self, msg: str, pos: Pos):
        super().__init__(f"{pos}: {msg}")
        self.pos = pos


# ── Environment (scoped symbol table) ─────────────────────────────

class Env:
    def __init__(self, parent: Optional[Env] = None):
        self._table: Dict[str, NurlType] = {}
        self._parent = parent

    def define(self, name: str, typ: NurlType, pos: Pos) -> None:
        if name in self._table:
            raise TypeError(f"'{name}' already defined in this scope", pos)
        self._table[name] = typ

    def lookup(self, name: str, pos: Pos) -> NurlType:
        if name in self._table:
            return self._table[name]
        if self._parent:
            return self._parent.lookup(name, pos)
        raise TypeError(f"undefined name '{name}'", pos)

    def assign(self, name: str, typ: NurlType, pos: Pos) -> None:
        """Check that name exists and the assigned type matches."""
        existing = self.lookup(name, pos)
        if not types_equal(existing, typ):
            raise TypeError(
                f"type mismatch in assignment to '{name}': "
                f"expected {type_str(existing)}, got {type_str(typ)}", pos)

    def child(self) -> Env:
        return Env(parent=self)


# ── Type-checker ───────────────────────────────────────────────────

class TypeChecker:
    def __init__(self, program: Program):
        self.program   = program
        self.globals   = Env()
        self.structs:  Dict[str, StructDecl] = {}
        self.enums: Dict[str, EnumDecl] = {}
        self._ret_type: Optional[NurlType] = None   # current function's return type
        # Trait/impl support (Group F)
        self._traits:       Dict[str, TraitDecl] = {}
        self._impl_methods: Dict[str, List[tuple]] = {}
        # method_name → list of (impl_type: NurlType, ret_type: NurlType)

        # Pre-register stdlib built-ins (no import required)
        for _name, _ft in _BUILTINS.items():
            self.globals._table[_name] = _ft

    def check(self) -> None:
        """Full type-check pass; raises TypeError on first error."""
        # Pass 1: register all top-level names (allows forward references)
        for decl in self.program.decls:
            self._register_decl(decl)
        # Pass 2: check bodies
        for decl in self.program.decls:
            self._check_decl(decl)

    # ── Pass 1: registration ──────────────────────────────────────

    def _register_decl(self, decl: Decl) -> None:
        if isinstance(decl, FnDecl):
            fn_type = FnType(
                ret    = decl.ret_type,
                params = [p.type for p in decl.params],
            )
            self.globals.define(decl.name, fn_type, decl.pos)

        elif isinstance(decl, StructDecl):
            self.structs[decl.name] = decl
            self.globals.define(decl.name, NamedType(decl.name), decl.pos)

        elif isinstance(decl, EnumDecl):
            self.enums[decl.name] = decl
            self.globals.define(decl.name, NamedType(decl.name), decl.pos)

        elif isinstance(decl, ConstDecl):
            self.globals.define(decl.name, decl.type, decl.pos)

        elif isinstance(decl, ImportDecl):
            pass   # imports resolved separately

        elif isinstance(decl, TraitDecl):
            self._traits[decl.name] = decl

        elif isinstance(decl, ImplDecl):
            for fn in decl.methods:
                if fn.name not in self._impl_methods:
                    self._impl_methods[fn.name] = []
                self._impl_methods[fn.name].append((decl.impl_type, fn.ret_type))

    # ── Pass 2: body checking ─────────────────────────────────────

    def _check_decl(self, decl: Decl) -> None:
        if isinstance(decl, FnDecl):
            if decl.type_params:
                return  # Generic function: skip body type-checking
            env = self.globals.child()
            for p in decl.params:
                env.define(p.name, p.type, p.pos)
            self._ret_type = decl.ret_type
            self._check_block(decl.body, env)
            self._ret_type = None

        elif isinstance(decl, ConstDecl):
            env = self.globals.child()
            t = self._infer_expr(decl.expr, env)
            self._assert_eq(decl.type, t, decl.pos,
                            f"constant '{decl.name}' type mismatch")

        elif isinstance(decl, EnumDecl):
            # Enum declarations don't have bodies to check - just validate variant types
            for variant in decl.variants:
                for payload_type in variant.payload:
                    self._validate_type(payload_type)

        elif isinstance(decl, TraitDecl):
            pass  # No body to check — trait is just an interface definition

        elif isinstance(decl, ImplDecl):
            for fn in decl.methods:
                env = self.globals.child()
                for p in fn.params:
                    env.define(p.name, p.type, p.pos)
                self._ret_type = fn.ret_type
                self._check_block(fn.body, env)
                self._ret_type = None

    # ── Block ─────────────────────────────────────────────────────

    def _check_block(self, block: Block, env: Env) -> NurlType:
        """Check each statement; return the type of the last expression."""
        last: NurlType = TV
        for stmt in block.stmts:
            last = self._check_stmt(stmt, env)
        return last

    # ── Statements ────────────────────────────────────────────────

    def _check_stmt(self, stmt: Stmt, env: Env) -> NurlType:
        if isinstance(stmt, LetStmt):
            t = self._infer_expr(stmt.expr, env)
            if stmt.type is not None:
                self._assert_eq(stmt.type, t, stmt.pos,
                                f"let '{stmt.name}' type mismatch")
                t = stmt.type
            env.define(stmt.name, t, stmt.pos)
            return TV

        if isinstance(stmt, SetStmt):
            t = self._infer_expr(stmt.expr, env)
            env.assign(stmt.name, t, stmt.pos)
            return TV

        if isinstance(stmt, FieldStoreStmt):
            self._infer_expr(stmt.obj, env)
            self._infer_expr(stmt.rhs, env)
            return TV

        if isinstance(stmt, ExprStmt):
            return self._infer_expr(stmt.expr, env)

        raise TypeError(f"unknown statement type {type(stmt)}", Pos(0, 0))

    # ── Expressions ───────────────────────────────────────────────

    def _infer_expr(self, expr: Expr, env: Env) -> NurlType:
        """Infer the type of expr, annotate expr.nurl_type, return the type."""
        t = self._infer(expr, env)
        expr.nurl_type = t
        return t

    def _infer(self, expr: Expr, env: Env) -> NurlType:
        if isinstance(expr, IntLit):
            return TI

        if isinstance(expr, FloatLit):
            return TF

        if isinstance(expr, StrLit):
            return TS

        if isinstance(expr, BoolLit):
            return TB

        if isinstance(expr, IdentExpr):
            return env.lookup(expr.name, expr.pos)

        if isinstance(expr, BlockExpr):
            child = env.child()
            return self._check_block(Block(expr.stmts, expr.pos), child)

        if isinstance(expr, RetExpr):
            t = self._infer_expr(expr.expr, env)
            if self._ret_type is None:
                raise TypeError("^ (return) outside function", expr.pos)
            self._assert_eq(self._ret_type, t, expr.pos,
                            f"return type mismatch: expected {type_str(self._ret_type)}")
            return TV   # ^ never "produces" a value in the current block

        if isinstance(expr, UnExpr):
            return self._infer_unary(expr, env)

        if isinstance(expr, BinExpr):
            return self._infer_binary(expr, env)

        if isinstance(expr, CallExpr):
            return self._infer_call(expr, env)

        if isinstance(expr, CondExpr):
            return self._infer_cond(expr, env)

        if isinstance(expr, LoopExpr):
            cond_t = self._infer_expr(expr.cond, env)
            self._assert_eq(TB, cond_t, expr.pos, "loop condition must be b (bool)")
            self._check_block(expr.body, env.child())
            return TV

        if isinstance(expr, MemberExpr):
            return self._infer_member(expr, env)

        if isinstance(expr, CastExpr):
            self._infer_expr(expr.expr, env)   # check sub-expr is well-typed
            return expr.target                  # result is the target type

        if isinstance(expr, EnumConstructor):
            return self._infer_enum_constructor(expr, env)

        if isinstance(expr, MatchExpr):
            return self._infer_match(expr, env)

        raise TypeError(f"unknown expression type {type(expr)}", Pos(0, 0))

    # ── Unary ─────────────────────────────────────────────────────

    def _infer_unary(self, expr: UnExpr, env: Env) -> NurlType:
        t = self._infer_expr(expr.expr, env)
        if expr.op == '!':
            self._assert_eq(TB, t, expr.pos, "! requires b (bool) operand")
            return TB
        if expr.op == '~':
            if not types_equal(t, TI) and not types_equal(t, TU) and not types_equal(t, TF):
                raise TypeError("~ requires numeric operand (i, u, or f)", expr.pos)
            return t
        raise TypeError(f"unknown unary op '{expr.op}'", expr.pos)

    # ── Binary ────────────────────────────────────────────────────

    _CMP_OPS  = {'<', '>', '==', '!=', '<=', '>='}
    _ARITH_OPS = {'+', '-', '*', '/', '%'}
    _SHIFT_OPS = {'<<', '>>'}
    _BOOL_OPS  = {'&', '|'}

    def _infer_binary(self, expr: BinExpr, env: Env) -> NurlType:
        lt = self._infer_expr(expr.left,  env)
        rt = self._infer_expr(expr.right, env)

        if not types_equal(lt, rt):
            raise TypeError(
                f"binary '{expr.op}': operand types differ: "
                f"{type_str(lt)} vs {type_str(rt)}", expr.pos)

        op = expr.op

        if op in self._CMP_OPS:
            # comparison works on i u f s; result is b
            if not any(types_equal(lt, t) for t in (TI, TU, TF, TS)):
                raise TypeError(
                    f"comparison '{op}' requires i, u, f, or s operands, got {type_str(lt)}",
                    expr.pos)
            return TB

        if op in self._ARITH_OPS:
            if not any(types_equal(lt, t) for t in (TI, TU, TF)):
                raise TypeError(
                    f"arithmetic '{op}' requires numeric operands (i, u, f), got {type_str(lt)}",
                    expr.pos)
            return lt

        if op in self._SHIFT_OPS:
            if not any(types_equal(lt, t) for t in (TI, TU)):
                raise TypeError(
                    f"shift '{op}' requires integer operands (i, u), got {type_str(lt)}",
                    expr.pos)
            return lt

        if op in self._BOOL_OPS:
            self._assert_eq(TB, lt, expr.pos, f"'{op}' requires b (bool) operands")
            return TB

        raise TypeError(f"unknown binary op '{op}'", expr.pos)

    # ── Call ──────────────────────────────────────────────────────

    def _infer_call(self, expr: CallExpr, env: Env) -> NurlType:
        # Generic call: compute instantiated return type, skip arg type checking
        if expr.type_args:
            self._infer_expr(expr.fn, env)
            fn_name = expr.fn.name if isinstance(expr.fn, IdentExpr) else None
            generic_decl = next(
                (d for d in self.program.decls
                 if isinstance(d, FnDecl) and d.name == fn_name and d.type_params),
                None,
            )
            # Annotate args (for side effects) but don't enforce types
            for arg in expr.args:
                self._infer_expr(arg, env)
            if generic_decl:
                type_map: Dict[str, NurlType] = {}
                for tp, ta_str in zip(generic_decl.type_params, expr.type_args):
                    type_map[tp] = _BASE.get(ta_str) or NamedType(ta_str)
                return _subst_type(generic_decl.ret_type, type_map)
            return TI  # fallback

        # Impl method dispatch: check before regular call resolution
        if isinstance(expr.fn, IdentExpr):
            fn_name = expr.fn.name
            if fn_name in self._impl_methods and expr.args:
                # Annotate all args
                for arg in expr.args:
                    self._infer_expr(arg, env)
                # Return type of the first registered impl (codegen handles dispatch)
                ret = self._impl_methods[fn_name][0][1]
                return ret

        fn_t = self._infer_expr(expr.fn, env)

        if not isinstance(fn_t, FnType):
            raise TypeError(
                f"called value is not a function (got {type_str(fn_t)})", expr.pos)

        if len(expr.args) != len(fn_t.params):
            raise TypeError(
                f"wrong number of arguments: expected {len(fn_t.params)}, "
                f"got {len(expr.args)}", expr.pos)

        for i, (arg, param_t) in enumerate(zip(expr.args, fn_t.params)):
            arg_t = self._infer_expr(arg, env)
            self._assert_eq(param_t, arg_t, arg.pos,
                            f"argument {i+1} type mismatch")

        return fn_t.ret

    # ── Conditional ───────────────────────────────────────────────

    def _infer_cond(self, expr: CondExpr, env: Env) -> NurlType:
        cond_t = self._infer_expr(expr.cond, env)
        self._assert_eq(TB, cond_t, expr.pos, "conditional condition must be b (bool)")
        then_t = self._infer_expr(expr.then, env)
        else_t = self._infer_expr(expr.else_, env)
        self._assert_eq(then_t, else_t, expr.pos,
                        f"conditional branches must have the same type: "
                        f"{type_str(then_t)} vs {type_str(else_t)}")
        return then_t

    # ── Member access ─────────────────────────────────────────────

    def _infer_member(self, expr: MemberExpr, env: Env) -> NurlType:
        obj_t = self._infer_expr(expr.obj, env)
        if not isinstance(obj_t, NamedType):
            raise TypeError(
                f"member access on non-struct type {type_str(obj_t)}", expr.pos)
        struct = self.structs.get(obj_t.name)
        if struct is None:
            raise TypeError(f"unknown struct '{obj_t.name}'", expr.pos)
        for field in struct.fields:
            if field.name == expr.field:
                return field.type
        raise TypeError(
            f"struct '{obj_t.name}' has no field '{expr.field}'", expr.pos)

    # ── Enum type checking ─────────────────────────────────────────

    def _validate_type(self, nurl_type: NurlType) -> None:
        """Validate that a type is well-formed and exists."""
        if isinstance(nurl_type, NamedType):
            if (nurl_type.name not in self.structs and
                nurl_type.name not in self.enums and
                nurl_type.name not in _BASE):
                # Check if it might be a variant name being used as a type
                for enum_decl in self.enums.values():
                    for variant in enum_decl.variants:
                        if variant.name == nurl_type.name:
                            raise TypeError(
                                f"'{nurl_type.name}' is a variant name, not a type name. "
                                f"Use '{enum_decl.name}' as the type.", Pos(0, 0))
                raise TypeError(f"unknown type '{nurl_type.name}'", Pos(0, 0))
        elif isinstance(nurl_type, BaseType):
            if nurl_type.name not in _BASE:
                raise TypeError(f"unknown base type '{nurl_type.name}'", Pos(0, 0))

    def _infer_enum_constructor(self, expr: EnumConstructor, env: Env) -> NurlType:
        """Type check enum constructor: @ EnumName { VariantName arg* }"""
        # Check enum exists
        if expr.enum_name not in self.enums:
            raise TypeError(f"unknown enum '{expr.enum_name}'", expr.pos)

        enum_decl = self.enums[expr.enum_name]

        # Find the variant
        variant = None
        for v in enum_decl.variants:
            if v.name == expr.variant_name:
                variant = v
                break

        if variant is None:
            raise TypeError(
                f"enum '{expr.enum_name}' has no variant '{expr.variant_name}'", expr.pos)

        # Check argument count matches payload count
        if len(expr.args) != len(variant.payload):
            raise TypeError(
                f"variant '{expr.variant_name}' expects {len(variant.payload)} arguments, got {len(expr.args)}",
                expr.pos)

        # Check argument types match payload types
        for i, (arg, expected_type) in enumerate(zip(expr.args, variant.payload)):
            arg_type = self._infer_expr(arg, env)
            self._assert_eq(expected_type, arg_type, arg.pos,
                            f"argument {i + 1} to variant '{expr.variant_name}'")

        return NamedType(expr.enum_name)

    def _infer_match(self, expr: MatchExpr, env: Env) -> NurlType:
        """Type check match expression: ?? expr { pattern → result ... }"""
        # Infer type of matched expression
        matched_type = self._infer_expr(expr.expr, env)

        # Ensure it's an enum type
        if not isinstance(matched_type, NamedType) or matched_type.name not in self.enums:
            raise TypeError(f"can only match on enum types, got {type_str(matched_type)}", expr.pos)

        enum_decl = self.enums[matched_type.name]

        # Check all cases and ensure they return the same type
        if not expr.cases:
            raise TypeError("match expression must have at least one case", expr.pos)

        # Get result type from first case
        first_case = expr.cases[0]
        case_env = env.child()

        # Validate first case pattern and bind variables
        self._validate_match_pattern(first_case.pattern, enum_decl, case_env)
        result_type = self._infer_expr(first_case.result, case_env)

        # Check remaining cases have the same result type
        for case in expr.cases[1:]:
            case_env = env.child()
            self._validate_match_pattern(case.pattern, enum_decl, case_env)
            case_result_type = self._infer_expr(case.result, case_env)
            self._assert_eq(result_type, case_result_type, case.result.pos,
                            f"match case result type mismatch")

        return result_type

    def _validate_match_pattern(self, pattern: MatchPattern, enum_decl: EnumDecl, env: Env) -> None:
        """Validate a match pattern and bind variables to the environment."""
        # Find the variant
        variant = None
        for v in enum_decl.variants:
            if v.name == pattern.variant_name:
                variant = v
                break

        if variant is None:
            raise TypeError(
                f"enum '{enum_decl.name}' has no variant '{pattern.variant_name}'", pattern.pos)

        # Check variable count matches payload count
        if len(pattern.variables) != len(variant.payload):
            raise TypeError(
                f"pattern for variant '{pattern.variant_name}' expects {len(variant.payload)} variables, got {len(pattern.variables)}",
                pattern.pos)

        # Bind pattern variables to their payload types
        for var_name, payload_type in zip(pattern.variables, variant.payload):
            env.define(var_name, payload_type, pattern.pos)

    # ── Assertion helper ──────────────────────────────────────────

    def _assert_eq(self, expected: NurlType, got: NurlType, pos: Pos, msg: str) -> None:
        if not types_equal(expected, got):
            raise TypeError(
                f"{msg}: expected {type_str(expected)}, got {type_str(got)}", pos)


def typecheck(program: Program) -> None:
    """Type-check program in place (annotates AST nodes). Raises TypeError."""
    TypeChecker(program).check()
