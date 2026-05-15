# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL → LLVM IR generator.

Emits LLVM IR text (.ll) directly from the type-checked AST.
Output can be compiled with:
    clang -O2 output.ll -o output          (native binary)
    clang -O2 output.ll libstd.a -o output (with stdlib)

LLVM IR type mapping
────────────────────
  i, u  →  i64
  f     →  double
  b     →  i1
  s     →  i8*       (null-terminated; length tracked separately when needed)
  v     →  void
  *T    →  T*
  [T    →  { i64, T* }    (fat pointer: len + data pointer)
  ?T    →  { i1, T }      (discriminated union: present flag + value)
  Named →  %Name

Struct member access: extractvalue (pass structs by value).

SSA phi nodes: same reserve-then-patch strategy as ir_gen.py.
"""

from __future__ import annotations
from typing import List, Optional, Dict, Set, Tuple
import sys
import os
from .ast_nodes import (
    Program, Decl, Stmt, Expr, Block, Param, NurlType,
    BaseType, PtrType, SliceType, OptType, FnType, NamedType,
    FnDecl, StructDecl, ConstDecl, ImportDecl,
    FnHeader, TraitDecl, ImplDecl,
    LetStmt, SetStmt, FieldStoreStmt, ExprStmt,
    IntLit, FloatLit, StrLit, BoolLit, IdentExpr,
    BinExpr, UnExpr, RetExpr, CallExpr, CondExpr,
    LoopExpr, MemberExpr, CastExpr, BlockExpr,
)
from .ir_gen import _collect_mutations   # reuse AST mutation scanner


# ── Generic helpers ────────────────────────────────────────────────

def _mangle_type_str(llvm_type: str) -> str:
    """LLVM type string → identifier fragment (matches nurlc.nu mangle_type)."""
    if llvm_type == 'i64':    return 'i64'
    if llvm_type == 'double': return 'f64'
    if llvm_type == 'i1':     return 'i1'
    if llvm_type == 'i8*':    return 'str'
    if llvm_type == 'void':   return 'void'
    if llvm_type.endswith('*'):
        return 'ptr_' + _mangle_type_str(llvm_type[:-1])
    if llvm_type.startswith('%'):
        return llvm_type[1:]
    return llvm_type


def _subst_nurl_type(t: NurlType, type_map: Dict[str, NurlType]) -> NurlType:
    """Substitute type variables in a NurlType."""
    if isinstance(t, NamedType) and t.name in type_map:
        return type_map[t.name]
    if isinstance(t, PtrType):
        return PtrType(_subst_nurl_type(t.inner, type_map))
    if isinstance(t, SliceType):
        return SliceType(_subst_nurl_type(t.inner, type_map))
    if isinstance(t, OptType):
        return OptType(_subst_nurl_type(t.inner, type_map))
    return t


def _instantiate_fn(template: FnDecl, new_name: str,
                    type_map: Dict[str, NurlType]) -> FnDecl:
    """Create a concrete FnDecl from a generic template by substituting types."""
    new_params = [
        Param(_subst_nurl_type(p.type, type_map), p.name, p.pos)
        for p in template.params
    ]
    new_ret = _subst_nurl_type(template.ret_type, type_map)
    return FnDecl(new_name, new_params, new_ret, template.body, template.pos)


# ── Type mapping ───────────────────────────────────────────────────

def _llvm_type(t: NurlType) -> str:
    if isinstance(t, BaseType):
        # 'u' is unsigned 8-bit byte (LLVM i8). The Python bootstrap
        # rarely needs to lower u-typed expressions because the only file
        # it compiles is compiler/nurlc.nu, which doesn't use 'u' — but
        # keep the mapping in sync with the self-hosted compiler so any
        # future bootstrap source can declare byte-typed values safely.
        return {'i': 'i64', 'u': 'i8', 'f': 'double',
                'b': 'i1',  's': 'i8*', 'v': 'void'}[t.name]
    if isinstance(t, PtrType):
        # void* is represented as i8* in LLVM
        if isinstance(t.inner, BaseType) and t.inner.name == 'v':
            return 'i8*'
        inner = _llvm_type(t.inner)
        return f'{inner}*'
    if isinstance(t, SliceType):
        inner = _llvm_type(t.inner)
        return f'{{ i64, {inner}* }}'
    if isinstance(t, OptType):
        inner = _llvm_type(t.inner)
        return f'{{ i1, {inner} }}'
    if isinstance(t, NamedType):
        return f'%{t.name}'
    return 'i8*'


def _is_float_type(t: Optional[NurlType]) -> bool:
    return isinstance(t, BaseType) and t.name == 'f'

def _is_bool_type(t: Optional[NurlType]) -> bool:
    return isinstance(t, BaseType) and t.name == 'b'

def _is_void_type(t: Optional[NurlType]) -> bool:
    return isinstance(t, BaseType) and t.name == 'v'

def _is_unsigned_int(t: Optional[NurlType]) -> bool:
    """True for unsigned integer types (currently only `u`/i8). When more
    sized unsigned types arrive (u16/u32/u64/...) extend this predicate."""
    return isinstance(t, BaseType) and t.name == 'u'


# ── Instruction builders ───────────────────────────────────────────

def _arith_instr(op: str, typ: Optional[NurlType]) -> str:
    """Map NURL binary op + type → LLVM arithmetic instruction mnemonic."""
    is_float = _is_float_type(typ)
    is_bool  = _is_bool_type(typ)
    is_uns   = _is_unsigned_int(typ)
    table = {
        '+': 'fadd' if is_float else 'add',
        '-': 'fsub' if is_float else 'sub',
        '*': 'fmul' if is_float else 'mul',
        '/': 'fdiv' if is_float else ('udiv' if is_uns else 'sdiv'),
        '%': 'frem' if is_float else ('urem' if is_uns else 'srem'),
        '&': 'and',
        '|': 'or',
        '<<': 'shl',
        '>>': 'lshr' if is_uns else 'ashr',
    }
    return table.get(op, op)


def _cmp_instr(op: str, typ: Optional[NurlType]) -> str:
    """Map NURL comparison op → LLVM icmp/fcmp predicate."""
    if _is_float_type(typ):
        return {
            '<': 'fcmp olt', '>': 'fcmp ogt',
            '==': 'fcmp oeq', '!=': 'fcmp one',
            '<=': 'fcmp ole', '>=': 'fcmp oge',
        }[op]
    if _is_unsigned_int(typ):
        return {
            '<': 'icmp ult', '>': 'icmp ugt',
            '==': 'icmp eq',  '!=': 'icmp ne',
            '<=': 'icmp ule', '>=': 'icmp uge',
        }[op]
    return {
        '<': 'icmp slt', '>': 'icmp sgt',
        '==': 'icmp eq',  '!=': 'icmp ne',
        '<=': 'icmp sle', '>=': 'icmp sge',
    }[op]


_CMP_OPS  = {'<', '>', '==', '!=', '<=', '>='}
_ARITH_OPS = {'+', '-', '*', '/', '%', '&', '|', '<<', '>>'}

# ── Built-in stdlib declarations ───────────────────────────────────
#
# Maps NURL function name → (LLVM C symbol, LLVM declare line).
# Implemented in stdlib/runtime.c; link with:
#   clang output.ll stdlib/runtime.o -o output
#
# User-facing names (print_int, …) are remapped to nurl_* C symbols.
# Runtime names (nurl_*) have NURL name == C symbol.

_BUILTIN_DECLS: Dict[str, Tuple[str, str]] = {
    # output helpers (matches NURL emit_header order)
    'nurl_print':    ('nurl_print',    'declare void @nurl_print(i8*)'),
    'nurl_eprint':   ('nurl_eprint',   'declare void @nurl_eprint(i8*)'),
    'nurl_eprintln': ('nurl_eprintln', 'declare void @nurl_eprintln(i8*)'),

    # user-facing I/O
    'print_int':  ('nurl_print_int',  'declare void @nurl_print_int(i64)'),
    'print_str':  ('nurl_print_str',  'declare void @nurl_print_str(i8*)'),
    'print_bool': ('nurl_print_bool', 'declare void @nurl_print_bool(i1)'),
    'read_int':   ('nurl_read_int',   'declare i64  @nurl_read_int()'),
    'nurl_read_line':    ('nurl_read_line',    'declare i8*  @nurl_read_line()'),
    'nurl_stdin_eof':    ('nurl_stdin_eof',    'declare i64  @nurl_stdin_eof()'),
    'nurl_flush_stdout': ('nurl_flush_stdout', 'declare void @nurl_flush_stdout()'),
    'nurl_flush_stderr': ('nurl_flush_stderr', 'declare void @nurl_flush_stderr()'),

    # string operations
    'nurl_str_len':    ('nurl_str_len',    'declare i64  @nurl_str_len(i8*)'),
    'nurl_str_get':    ('nurl_str_get',    'declare i64  @nurl_str_get(i8*, i64)'),
    'nurl_str_eq':     ('nurl_str_eq',     'declare i64  @nurl_str_eq(i8*, i8*)'),
    'nurl_str_cmp':    ('nurl_str_cmp',    'declare i64  @nurl_str_cmp(i8*, i8*)'),
    'nurl_str_cat':    ('nurl_str_cat',    'declare i8*  @nurl_str_cat(i8*, i8*)'),
    'nurl_str_cat3':   ('nurl_str_cat3',   'declare i8*  @nurl_str_cat3(i8*, i8*, i8*)'),
    'nurl_str_cat4':   ('nurl_str_cat4',   'declare i8*  @nurl_str_cat4(i8*, i8*, i8*, i8*)'),
    'nurl_str_int':    ('nurl_str_int',    'declare i8*  @nurl_str_int(i64)'),
    'nurl_str_float':  ('nurl_str_float',  'declare i8*  @nurl_str_float(double)'),
    'nurl_str_to_int': ('nurl_str_to_int', 'declare i64  @nurl_str_to_int(i8*)'),
    'nurl_str_to_float': ('nurl_str_to_float', 'declare double @nurl_str_to_float(i8*)'),
    'nurl_str_slice':  ('nurl_str_slice',  'declare i8*  @nurl_str_slice(i8*, i64, i64)'),
    'nurl_str_starts': ('nurl_str_starts', 'declare i64  @nurl_str_starts(i8*, i8*)'),
    'nurl_str_find':   ('nurl_str_find',   'declare i64  @nurl_str_find(i8*, i8*)'),

    # hashmap (string → i64)
    'nurl_map_new':  ('nurl_map_new',  'declare i64  @nurl_map_new()'),
    'nurl_map_put':  ('nurl_map_put',  'declare void @nurl_map_put(i64, i8*, i64)'),
    'nurl_map_get':  ('nurl_map_get',  'declare i64  @nurl_map_get(i64, i8*)'),
    'nurl_map_has':  ('nurl_map_has',  'declare i64  @nurl_map_has(i64, i8*)'),
    'nurl_map_del':  ('nurl_map_del',  'declare void @nurl_map_del(i64, i8*)'),
    'nurl_map_size': ('nurl_map_size', 'declare i64  @nurl_map_size(i64)'),
    'nurl_map_free': ('nurl_map_free', 'declare void @nurl_map_free(i64)'),

    # char classification
    'nurl_is_alpha':  ('nurl_is_alpha',  'declare i64  @nurl_is_alpha(i64)'),
    'nurl_is_digit':  ('nurl_is_digit',  'declare i64  @nurl_is_digit(i64)'),
    'nurl_is_space':  ('nurl_is_space',  'declare i64  @nurl_is_space(i64)'),
    'nurl_is_alnum_': ('nurl_is_alnum_', 'declare i64  @nurl_is_alnum_(i64)'),

    # file & process
    'nurl_read_file':   ('nurl_read_file',   'declare i8*  @nurl_read_file(i8*)'),
    'nurl_file_exists': ('nurl_file_exists', 'declare i64  @nurl_file_exists(i8*)'),
    'nurl_exit':      ('nurl_exit',      'declare void @nurl_exit(i64)'),
    'nurl_argc':       ('nurl_argc',       'declare i64  @nurl_argc()'),
    'nurl_argv':       ('nurl_argv',       'declare i8*  @nurl_argv(i64)'),
    'nurl_argv_count': ('nurl_argv_count', 'declare i64  @nurl_argv_count()'),
    'nurl_argv_get':   ('nurl_argv_get',   'declare i8*  @nurl_argv_get(i64)'),

    # lexer
    'nurl_lex_new':       ('nurl_lex_new',       'declare i64  @nurl_lex_new(i8*, i8*)'),
    'nurl_lex_type':      ('nurl_lex_type',       'declare i64  @nurl_lex_type(i64)'),
    'nurl_lex_val':       ('nurl_lex_val',        'declare i8*  @nurl_lex_val(i64)'),
    'nurl_lex_inum':      ('nurl_lex_inum',       'declare i64    @nurl_lex_inum(i64)'),
    'nurl_lex_fnum':      ('nurl_lex_fnum',       'declare double @nurl_lex_fnum(i64)'),
    'nurl_lex_advance':   ('nurl_lex_advance',    'declare void   @nurl_lex_advance(i64)'),
    'nurl_lex_peek_type': ('nurl_lex_peek_type',  'declare i64  @nurl_lex_peek_type(i64)'),
    'nurl_lex_peek2_type':('nurl_lex_peek2_type', 'declare i64  @nurl_lex_peek2_type(i64)'),
    'nurl_lex_peek3_type':('nurl_lex_peek3_type', 'declare i64  @nurl_lex_peek3_type(i64)'),
    'nurl_lex_peek4_type':('nurl_lex_peek4_type', 'declare i64  @nurl_lex_peek4_type(i64)'),
    'nurl_lex_line':       ('nurl_lex_line',        'declare i64  @nurl_lex_line(i64)'),
    'nurl_lex_col':        ('nurl_lex_col',         'declare i64  @nurl_lex_col(i64)'),
    'nurl_lex_line_text':  ('nurl_lex_line_text',   'declare i8*  @nurl_lex_line_text(i64)'),
    'nurl_diag_caret':     ('nurl_diag_caret',      'declare i8*  @nurl_diag_caret(i64)'),
    'nurl_lex_filename':   ('nurl_lex_filename',    'declare i8*  @nurl_lex_filename(i64)'),
    'nurl_lex_cur_start':  ('nurl_lex_cur_start',   'declare i64  @nurl_lex_cur_start(i64)'),
    'nurl_lex_src_slice':  ('nurl_lex_src_slice',   'declare i8*  @nurl_lex_src_slice(i64, i64, i64)'),
    'nurl_lex_set_pos':    ('nurl_lex_set_pos',     'declare void @nurl_lex_set_pos(i64, i64)'),
    'nurl_print_buf_start':('nurl_print_buf_start', 'declare void @nurl_print_buf_start()'),
    'nurl_print_buf_stop': ('nurl_print_buf_stop',  'declare i8*  @nurl_print_buf_stop()'),
    'nurl_print_buf_reset':('nurl_print_buf_reset', 'declare void @nurl_print_buf_reset()'),

    # symbol table
    'nurl_sym_new':  ('nurl_sym_new',  'declare i64  @nurl_sym_new()'),
    'nurl_sym_def':  ('nurl_sym_def',  'declare void @nurl_sym_def(i64, i8*, i8*)'),
    'nurl_sym_get':  ('nurl_sym_get',  'declare i8*  @nurl_sym_get(i64, i8*)'),
    'nurl_sym_push': ('nurl_sym_push', 'declare void @nurl_sym_push(i64)'),
    'nurl_sym_pop':  ('nurl_sym_pop',  'declare void @nurl_sym_pop(i64)'),

    # codegen helpers
    'nurl_cg_new':   ('nurl_cg_new',   'declare i64  @nurl_cg_new()'),
    'nurl_cg_reg':   ('nurl_cg_reg',   'declare i8*  @nurl_cg_reg(i64)'),
    'nurl_cg_lbl':   ('nurl_cg_lbl',   'declare i8*  @nurl_cg_lbl(i64, i8*)'),
    'nurl_cg_reset': ('nurl_cg_reset', 'declare void @nurl_cg_reset(i64)'),

    # type sideband
    'nurl_get_last_type': ('nurl_get_last_type', 'declare i8*  @nurl_get_last_type()'),
    'nurl_set_last_type': ('nurl_set_last_type', 'declare void @nurl_set_last_type(i8*)'),

    # memory allocation
    'nurl_malloc':  ('nurl_malloc',  'declare i8*  @nurl_malloc(i64)'),
    'nurl_alloc':   ('nurl_alloc',   'declare i8*  @nurl_alloc(i64)'),
    'nurl_zalloc':  ('nurl_zalloc',  'declare i8*  @nurl_zalloc(i64)'),
    'nurl_realloc': ('nurl_realloc', 'declare i8*  @nurl_realloc(i8*, i64)'),
    'nurl_free':    ('nurl_free',    'declare void @nurl_free(i8*)'),
    'nurl_memcpy':  ('nurl_memcpy',  'declare void @nurl_memcpy(i8*, i8*, i64)'),
    'nurl_peek':    ('nurl_peek',    'declare i64  @nurl_peek(i8*, i64)'),
    'nurl_poke':    ('nurl_poke',    'declare void @nurl_poke(i8*, i64, i64)'),

    # CLI tooling: env, cwd, stdin slurp, directory listing
    'nurl_env_get':        ('nurl_env_get',        'declare i8*  @nurl_env_get(i8*)'),
    'nurl_env_set':        ('nurl_env_set',        'declare i64  @nurl_env_set(i8*, i8*)'),
    'nurl_env_unset':      ('nurl_env_unset',      'declare i64  @nurl_env_unset(i8*)'),
    'nurl_cwd':            ('nurl_cwd',            'declare i8*  @nurl_cwd()'),
    'nurl_chdir':          ('nurl_chdir',          'declare i64  @nurl_chdir(i8*)'),
    'nurl_read_all_stdin': ('nurl_read_all_stdin', 'declare i8*  @nurl_read_all_stdin()'),
    'nurl_dir_list_open':  ('nurl_dir_list_open',  'declare i64  @nurl_dir_list_open(i8*)'),
    'nurl_dir_list_next':  ('nurl_dir_list_next',  'declare i8*  @nurl_dir_list_next(i64)'),
    'nurl_dir_list_close': ('nurl_dir_list_close', 'declare void @nurl_dir_list_close(i64)'),

    # logging level (process-wide; backs stdlib/std/log.nu)
    'nurl_log_level_get': ('nurl_log_level_get', 'declare i64  @nurl_log_level_get()'),
    'nurl_log_level_set': ('nurl_log_level_set', 'declare void @nurl_log_level_set(i64)'),
}


# ── String literal helpers ─────────────────────────────────────────

def _encode_str(s: str) -> Tuple[str, int]:
    """Return (LLVM string literal, byte length including null terminator)."""
    buf = []
    for ch in s:
        code = ord(ch)
        if 32 <= code <= 126 and ch not in ('"', '\\'):
            buf.append(ch)
        else:
            buf.append(f'\\{code:02X}')
    buf.append('\\00')
    return ''.join(buf), len(s.encode('utf-8')) + 1


# ── LLVM IR Generator ──────────────────────────────────────────────

class LLVMGen:
    def __init__(self, program: Program):
        self.program = program

        # Global declarations emitted before function bodies
        self._globals: List[str]   = []
        self._str_idx: int         = 0
        self._str_cache: Dict[str, str] = {}  # value → global name

        # Top-level ConstDecl names — accessed via load/store in IR
        self._global_names: set = set()

        # All declared function names — so call codegen can emit @name even
        # inside generic bodies where nurl_type hasn't been set by the typechecker
        self._fn_names: set = set()

        # Per-function output (patchable list)
        self._lines: List[Optional[str]] = []

        # Per-function state
        self._reg:        int             = 0
        self._lbl:        int             = 0
        self._vars:       Dict[str, str]  = {}  # name → LLVM value (or ptr)
        self._var_types:  Dict[str, str]  = {}  # name → LLVM type string
        self._var_ptrs:   Dict[str, str]  = {}  # name → alloca ptr (if let-bound)
        self._cur_label:  str             = 'entry'
        self._did_ret:    bool            = False
        self._fn_str_base: int            = 0   # str_idx at function start
        self._last_type:  str             = 'i64'

        # Struct field index lookup
        self._structs:    Dict[str, StructDecl] = {}

        # Generic function support (Group E)
        self._generic_templates:   Dict[str, FnDecl]       = {}  # name → template
        self._instantiated:        Set[str]                 = set()  # mangled names done
        self._pending_instantiations: List[Tuple[str, FnDecl]] = []  # (mangled, concrete)

        # Trait/impl support (Group F)
        # method_name → [(llvm_arg_type, mangled_fn_name, llvm_ret_type)]
        self._impl_dispatch: Dict[str, List[Tuple[str, str, str]]] = {}

    # ── output primitives ─────────────────────────────────────────

    def _emit(self, line: str) -> None:
        self._lines.append(line)

    def _indent(self, line: str) -> None:
        self._lines.append('  ' + line)

    def _reserve_line(self) -> int:
        idx = len(self._lines)
        self._lines.append(None)
        return idx

    def _patch_line(self, idx: int, line: str) -> None:
        self._lines[idx] = line

    def _set_label(self, lbl: str) -> None:
        self._emit(f'{lbl}:')
        self._cur_label = lbl

    def _set_last_type(self, t: Optional[NurlType] | str) -> None:
        if isinstance(t, str):
            self._last_type = t
        elif t is not None:
            self._last_type = _llvm_type(t)
        else:
            self._last_type = 'i64'

    # ── register / label allocation ───────────────────────────────

    def _fresh_reg(self) -> str:
        r = f'%r{self._reg}'
        self._reg += 1
        return r

    def _fresh_lbl(self, hint: str) -> str:
        l = f'{hint}_{self._lbl}'
        self._lbl += 1
        return l

    # ── string global ─────────────────────────────────────────────

    def _str_global(self, value: str) -> str:
        """Return the LLVM global name for a string constant.

        No deduplication — each call creates a fresh @.str.N, matching
        the NURL compiler's behaviour (emit_str_global always increments).
        """
        name = f'@.str.{self._str_idx}'
        self._str_idx += 1
        encoded, length = _encode_str(value)
        self._globals.append(
            f'{name} = private unnamed_addr constant [{length} x i8] c"{encoded}"'
        )
        return name

    # ── public entry ──────────────────────────────────────────────

    def generate(self) -> str:
        # Index structs
        for decl in self.program.decls:
            if isinstance(decl, StructDecl):
                self._structs[decl.name] = decl

        # Pre-scan ConstDecl names so they are known as globals during codegen
        for decl in self.program.decls:
            if isinstance(decl, ConstDecl):
                self._global_names.add(decl.name)

        # Detect 'main' function — it gets special treatment
        main_decl = next(
            (d for d in self.program.decls
             if isinstance(d, FnDecl) and d.name == 'main'),
            None
        )

        # ── Build header: declares first (matches NURL compiler order) ──
        out: List[str] = []
        out.append(f'; NURL compiler output ({os.path.basename(self.program.file)})')
        out.append('; link: clang <this.ll> stdlib/runtime.o -o out')
        out.append('')

        # External declarations (libc + runtime) — emitted before any globals
        out.append('declare i32  @puts(i8*)')
        out.append('declare i32  @printf(i8*, ...)')
        out.append('declare i8*  @malloc(i64)')
        out.append('declare void @free(i8*)')
        out.append('declare void @nurl_init(i32, i8**)')
        for _, decl_line in _BUILTIN_DECLS.values():
            out.append(decl_line)
        out.append('')

        # Pre-scan: collect generic templates and all function names
        for decl in self.program.decls:
            if isinstance(decl, FnDecl):
                self._fn_names.add(decl.name)
                if decl.type_params:
                    self._generic_templates[decl.name] = decl
        # Also register all builtins as known function names
        self._fn_names.update(_BUILTIN_DECLS.keys())

        # ── Emit declarations in source order, interleaving globals/structs/functions ──
        for decl in self.program.decls:
            if isinstance(decl, ConstDecl):
                lt  = _llvm_type(decl.type)
                val = self._eval_const_init(decl.expr)
                out.append(f'@{decl.name} = global {lt} {val}')
                out.append('')   # blank line after each const global

            elif isinstance(decl, StructDecl):
                fields = ', '.join(_llvm_type(f.type) for f in decl.fields)
                out.append(f'%{decl.name} = type {{ {fields} }}')
                out.append('')

            elif isinstance(decl, FnDecl):
                if decl.type_params:
                    continue  # Generic template: emit only on instantiation
                llvm_name = '_nurl_main' if decl.name == 'main' else decl.name
                self._gen_fn(decl, llvm_name)
                out.extend(
                    line for line in self._lines if line is not None
                )
                out.append('')
                # Emit string globals that were created during this function
                for g in self._globals[self._fn_str_base:]:
                    out.append(g)
                self._fn_str_base = len(self._globals)
                self._lines = []

                # Emit main wrapper immediately after main function
                if decl.name == 'main' and main_decl is not None:
                    out.extend(self._make_main_wrapper(main_decl).splitlines())
                    out.append('')

            elif isinstance(decl, TraitDecl):
                pass  # Trait declarations produce no LLVM IR

            elif isinstance(decl, ImplDecl):
                impl_llvm_type = _llvm_type(decl.impl_type)
                mangle_sfx     = _mangle_type_str(impl_llvm_type)
                for fn in decl.methods:
                    mangled_name = f'{fn.name}__{mangle_sfx}'
                    ret_llvm     = _llvm_type(fn.ret_type)
                    if fn.name not in self._impl_dispatch:
                        self._impl_dispatch[fn.name] = []
                    self._impl_dispatch[fn.name].append(
                        (impl_llvm_type, mangled_name, ret_llvm)
                    )
                    self._fn_names.add(mangled_name)
                    self._gen_fn(fn, mangled_name)
                    out.extend(
                        line for line in self._lines if line is not None
                    )
                    out.append('')
                    for g in self._globals[self._fn_str_base:]:
                        out.append(g)
                    self._fn_str_base = len(self._globals)
                    self._lines = []

        # ── Emit deferred generic instantiations (loop handles transitive generics) ──
        while self._pending_instantiations:
            pending = list(self._pending_instantiations)
            self._pending_instantiations = []
            for mangled_name, concrete in pending:
                self._gen_fn(concrete, mangled_name)
                out.extend(
                    line for line in self._lines if line is not None
                )
                out.append('')
                for g in self._globals[self._fn_str_base:]:
                    out.append(g)
                self._fn_str_base = len(self._globals)
                self._lines = []

        return '\n'.join(out) + '\n'

    # ── main wrapper ──────────────────────────────────────────────

    def _make_main_wrapper(self, decl: FnDecl) -> str:
        """
        Emit a C-ABI `i32 @main()` that calls `@_nurl_main` and returns i32.

        This is required because:
        - C runtime expects `int main()` (i32)
        - NURL's  `→ i` maps to i64
        - NURL's  `→ v` maps to void (exit code 0)
        """
        ret = decl.ret_type
        init = ('  call void @nurl_init(i32 %argc, i8** %argv)\n')
        if isinstance(ret, BaseType) and ret.name == 'v':
            return (
                'define i32 @main(i32 %argc, i8** %argv) {\n'
                'entry:\n'
                f'{init}'
                '  call void @_nurl_main()\n'
                '  ret i32 0\n'
                '}'
            )
        else:
            # i, u, f → truncate/convert to i32
            call_ret = _llvm_type(ret)
            trunc = (f'  %_ret = call {call_ret} @_nurl_main()\n'
                     f'  %_exit = trunc {call_ret} %_ret to i32')
            if isinstance(ret, BaseType) and ret.name == 'f':
                trunc = (f'  %_ret = call double @_nurl_main()\n'
                         f'  %_intf = fptosi double %_ret to i64\n'
                         f'  %_exit = trunc i64 %_intf to i32')
            return (
                'define i32 @main(i32 %argc, i8** %argv) {\n'
                'entry:\n'
                f'{init}'
                f'{trunc}\n'
                '  ret i32 %_exit\n'
                '}'
            )

    # ── constant initializer evaluator ───────────────────────────

    def _eval_const_init(self, expr: Expr) -> str:
        """Return the LLVM literal value for a constant initializer."""
        if isinstance(expr, IntLit):
            return str(expr.value)
        if isinstance(expr, BoolLit):
            return '1' if expr.value else '0'
        if isinstance(expr, FloatLit):
            import struct
            packed = struct.pack('>d', expr.value)
            return '0x' + packed.hex().upper()
        return '0'  # fallback (strings etc.)

    # ── function generation ───────────────────────────────────────

    def _gen_fn(self, decl: FnDecl, llvm_name: str = '') -> None:
        self._reg       = 0
        self._lbl       = 1
        self._vars      = {}
        self._var_types = {}
        self._var_ptrs  = {}
        self._cur_label = 'entry'
        self._did_ret   = False
        self._lines     = []
        self._fn_str_base = len(self._globals)

        name  = llvm_name or decl.name
        ret_t = _llvm_type(decl.ret_type)

        # Parameters — structs passed by value
        params_parts = []
        for p in decl.params:
            lt = _llvm_type(p.type)
            params_parts.append(f'{lt} %{p.name}')
            self._vars[p.name]      = f'%{p.name}'
            self._var_types[p.name] = lt

        params_str = ', '.join(params_parts)
        self._emit(f'define {ret_t} @{name}({params_str}) {{')
        self._set_label('entry')

        # Pre-allocate return-value slot (matching NURL compiler pattern)
        if not _is_void_type(decl.ret_type):
            ret_ptr = self._fresh_reg()
            self._indent(f'{ret_ptr} = alloca {ret_t}')

        last_reg = self._gen_block(decl.body)

        # 'undef' and 'undef' are sentinels, not real LLVM values
        if last_reg in ('undef', 'undef'):
            last_reg = None

        if not self._did_ret:
            if _is_void_type(decl.ret_type):
                self._indent('ret void')
            elif last_reg is not None:
                self._indent(f'ret {ret_t} {last_reg}')
            else:
                if not _is_void_type(decl.ret_type):
                    self._indent(f'ret {ret_t} undef')

        self._emit('}')

    # ── block ─────────────────────────────────────────────────────

    def _gen_block(self, block: Block) -> Optional[str]:
        last: Optional[str] = None
        for stmt in block.stmts:
            last = self._gen_stmt(stmt)
        return last

    # ── statements ────────────────────────────────────────────────

    def _gen_stmt(self, stmt: Stmt) -> Optional[str]:
        if isinstance(stmt, LetStmt):
            reg  = self._gen_expr(stmt.expr)
            lt   = self._last_type   # use actual generated type (handles generics)
            # Emit alloca + store (matching NURL compiler pattern)
            ptr  = self._fresh_reg()
            self._indent(f'{ptr} = alloca {lt}')
            self._indent(f'store {lt} {reg}, {lt}* {ptr}')
            self._vars[stmt.name]      = reg
            self._var_types[stmt.name] = lt
            self._var_ptrs[stmt.name]  = ptr
            return reg

        if isinstance(stmt, SetStmt):
            reg = self._gen_expr(stmt.expr)
            lt  = self._last_type   # use actual generated type (handles generics)
            if stmt.name in self._global_names:
                self._indent(f'store {lt} {reg}, {lt}* @{stmt.name}')
            elif stmt.name in self._var_ptrs:
                ptr = self._var_ptrs[stmt.name]
                vt  = self._var_types.get(stmt.name, lt)
                self._indent(f'store {vt} {reg}, {vt}* {ptr}')
            else:
                self._vars[stmt.name] = reg
            return reg

        if isinstance(stmt, FieldStoreStmt):
            # Emit GEP + store through pointer
            ptr_val  = self._gen_expr(stmt.obj)
            ptr_type = stmt.obj.nurl_type
            if not isinstance(ptr_type, PtrType):
                raise RuntimeError(f"field store on non-pointer: {ptr_type}")
            inner = ptr_type.inner
            if not isinstance(inner, NamedType):
                raise RuntimeError(f"field store into non-struct pointer: {inner}")
            struct = self._structs.get(inner.name)
            if struct is None:
                raise RuntimeError(f"unknown struct: {inner.name}")
            field_idx = next(
                (i for i, f in enumerate(struct.fields) if f.name == stmt.field), None
            )
            if field_idx is None:
                raise RuntimeError(f"no field {stmt.field!r} in {inner.name}")
            field_type    = struct.fields[field_idx].type
            ft_ir         = _llvm_type(field_type)
            struct_ir     = f'%{inner.name}'
            ptr_ir        = f'{struct_ir}*'
            rhs_val       = self._gen_expr(stmt.rhs)
            gep           = self._fresh_reg()
            self._indent(f'{gep} = getelementptr {struct_ir}, {ptr_ir} {ptr_val}, i32 0, i32 {field_idx}')
            self._indent(f'store {ft_ir} {rhs_val}, {ft_ir}* {gep}')
            self._set_last_type(ft_ir)
            return rhs_val

        if isinstance(stmt, ExprStmt):
            return self._gen_expr(stmt.expr)

        return None

    # ── expressions ───────────────────────────────────────────────

    def _gen_expr(self, expr: Expr) -> str:
        if isinstance(expr, IntLit):
            self._set_last_type('i64')
            return str(expr.value)

        if isinstance(expr, FloatLit):
            self._set_last_type('double')
            # LLVM requires hex float for exact representation
            import struct
            packed = struct.pack('>d', expr.value)
            hexval = '0x' + packed.hex().upper()
            return hexval

        if isinstance(expr, StrLit):
            self._set_last_type('i8*')
            gname  = self._str_global(expr.value)
            _, length = _encode_str(expr.value)
            res = self._fresh_reg()
            self._indent(
                f'{res} = getelementptr [{length} x i8], '
                f'[{length} x i8]* {gname}, i64 0, i64 0'
            )
            return res

        if isinstance(expr, BoolLit):
            self._set_last_type('i1')
            return '1' if expr.value else '0'

        if isinstance(expr, IdentExpr):
            lt_str = 'i64'
            if expr.name in self._global_names:
                lt  = _llvm_type(expr.nurl_type) if isinstance(expr.nurl_type, NurlType) else 'i64'
                lt_str = lt
                self._set_last_type(lt)
                reg = self._fresh_reg()
                self._indent(f'{reg} = load {lt}, {lt}* @{expr.name}')
                return reg
            if expr.name in self._var_ptrs:
                lt  = self._var_types.get(expr.name, 'i64')
                lt_str = lt
                self._set_last_type(lt)
                reg = self._fresh_reg()
                self._indent(f'{reg} = load {lt}, {lt}* {self._var_ptrs[expr.name]}')
                return reg
            lt_str = self._var_types.get(expr.name, 'i64')
            self._set_last_type(lt_str)
            return self._vars.get(expr.name, f'%{expr.name}')

        if isinstance(expr, BinExpr):
            return self._gen_binary(expr)

        if isinstance(expr, UnExpr):
            return self._gen_unary(expr)

        if isinstance(expr, RetExpr):
            val = self._gen_expr(expr.expr)
            t   = self._last_type   # use actual generated type (handles generics)
            if t == 'void':
                self._indent('ret void')
            else:
                self._indent(f'ret {t} {val}')
            self._did_ret = True
            self._set_last_type('void')
            return val

        if isinstance(expr, CallExpr):
            return self._gen_call(expr)

        if isinstance(expr, CondExpr):
            return self._gen_cond(expr)

        if isinstance(expr, LoopExpr):
            return self._gen_loop(expr)

        if isinstance(expr, MemberExpr):
            return self._gen_member(expr)

        if isinstance(expr, CastExpr):
            return self._gen_cast(expr)

        if isinstance(expr, BlockExpr):
            # BlockExpr DOES NOT update last_type if empty (matches nurlc.nu)
            result = self._gen_block(Block(expr.stmts, expr.pos))
            return result or 'undef'

        raise RuntimeError(f"unhandled expr type {type(expr).__name__}")

    # ── binary ────────────────────────────────────────────────────

    def _gen_binary(self, expr: BinExpr) -> str:
        lv = self._gen_expr(expr.left)
        t_from_gen = self._last_type   # authoritative LLVM type from code gen
        rv = self._gen_expr(expr.right)
        lt = expr.left.nurl_type
        # Use code-gen type when AST type is unresolved:
        # - None (pre-typechecked) or Field sentinel (body skipped for generics)
        # - NamedType (unsubstituted type variable like T, K, V)
        if not isinstance(lt, NurlType) or isinstance(lt, NamedType):
            t = t_from_gen
            # Synthetic NurlType for arithmetic helper (float vs int)
            instr_lt: Optional[NurlType] = BaseType('f') if t_from_gen == 'double' else BaseType('i')
        else:
            t = _llvm_type(lt)
            instr_lt = lt
        op = expr.op
        res = self._fresh_reg()

        if op in _CMP_OPS:
            instr = _cmp_instr(op, instr_lt)
            self._indent(f'{res} = {instr} {t} {lv}, {rv}')
            self._set_last_type('i1')
        elif op in _ARITH_OPS:
            instr = _arith_instr(op, instr_lt)
            self._indent(f'{res} = {instr} {t} {lv}, {rv}')
            self._set_last_type(t)
        else:
            self._indent(f'{res} = add i64 {lv}, 0  ; unknown op {op}')
            self._set_last_type('i64')
        return res

    # ── unary ─────────────────────────────────────────────────────

    def _gen_unary(self, expr: UnExpr) -> str:
        v   = self._gen_expr(expr.expr)
        t   = expr.expr.nurl_type
        lt  = _llvm_type(t) if isinstance(t, NurlType) else self._last_type
        res = self._fresh_reg()
        if expr.op == '!':
            # logical not: xor i1 %v, 1
            self._indent(f'{res} = xor i1 {v}, 1')
            self._set_last_type('i1')
        elif expr.op == '~':
            if _is_float_type(t):
                self._indent(f'{res} = fneg double {v}')
                self._set_last_type('double')
            else:
                self._indent(f'{res} = xor {lt} {v}, -1')
                self._set_last_type(lt)
        else:
            self._indent(f'{res} = add i64 {v}, 0  ; unknown unary {expr.op}')
            self._set_last_type('i64')
        return res

    # ── call ──────────────────────────────────────────────────────

    def _gen_impl_call(self, expr: CallExpr) -> str:
        """Emit a call to a trait impl method, dispatched on first arg's LLVM type."""
        fn_name = expr.fn.name
        dispatch_list = self._impl_dispatch[fn_name]

        # Generate all args; capture first arg's LLVM type for dispatch
        arg_parts: List[str] = []
        first_arg_type = 'i64'
        for i, arg in enumerate(expr.args):
            arg_val = self._gen_expr(arg)
            arg_t   = self._last_type
            if i == 0:
                first_arg_type = arg_t
            arg_parts.append(f'{arg_t} {arg_val}')

        args_str = ', '.join(arg_parts)

        # Find matching impl by first arg's LLVM type
        for (impl_arg_type, mangled_name, ret_type) in dispatch_list:
            if impl_arg_type == first_arg_type:
                if ret_type == 'void':
                    self._indent(f'call void @{mangled_name}({args_str})')
                    self._set_last_type('void')
                    return 'undef'
                else:
                    res = self._fresh_reg()
                    self._indent(f'{res} = call {ret_type} @{mangled_name}({args_str})')
                    self._set_last_type(ret_type)
                    return res

        raise RuntimeError(
            f'no impl of {fn_name} for first arg type {first_arg_type}'
        )

    def _gen_call(self, expr: CallExpr) -> str:
        # Generic call: monomorphise and emit to mangled function name
        if expr.type_args and isinstance(expr.fn, IdentExpr):
            return self._gen_generic_call(expr)

        # Impl method call: dispatch based on first arg's LLVM type
        if isinstance(expr.fn, IdentExpr) and expr.fn.name in self._impl_dispatch:
            return self._gen_impl_call(expr)

        # Global functions are referenced with @name in LLVM IR.
        # Built-in stdlib names are remapped to their C symbol (nurl_*).
        # Also handles generic function bodies where nurl_type is not yet set.
        if isinstance(expr.fn, IdentExpr) and (
            isinstance(expr.fn.nurl_type, FnType)
            or expr.fn.name in _BUILTIN_DECLS
            or expr.fn.name in self._fn_names
        ):
            nurl_name = expr.fn.name
            llvm_sym  = _BUILTIN_DECLS[nurl_name][0] if nurl_name in _BUILTIN_DECLS else nurl_name
            fn_name   = f'@{llvm_sym}'
        else:
            fn_name = self._gen_expr(expr.fn)

        ret_t   = _llvm_type(expr.nurl_type) if isinstance(expr.nurl_type, NurlType) else 'i64'

        # Build arg list with types
        arg_parts = []
        for arg in expr.args:
            arg_val = self._gen_expr(arg)
            arg_t   = self._last_type   # use generated type (handles generics)
            arg_parts.append(f'{arg_t} {arg_val}')

        args_str = ', '.join(arg_parts)

        if _is_void_type(expr.nurl_type):
            self._indent(f'call void {fn_name}({args_str})')
            self._set_last_type('void')
            return 'undef'
        else:
            res = self._fresh_reg()
            self._indent(f'{res} = call {ret_t} {fn_name}({args_str})')
            self._set_last_type(ret_t)
            return res

    def _gen_generic_call(self, expr: CallExpr) -> str:
        """Emit a call to a monomorphised generic function."""
        fn_name = expr.fn.name
        template = self._generic_templates.get(fn_name)
        if template is None:
            raise RuntimeError(f'unknown generic function: {fn_name}')

        # Build type map: param-name → concrete NurlType
        type_map: Dict[str, NurlType] = {}
        for tp, ta_str in zip(template.type_params, expr.type_args):
            if ta_str in ('i', 'u', 'f', 'b', 's', 'v'):
                type_map[tp] = BaseType(ta_str)
            else:
                type_map[tp] = NamedType(ta_str)

        # Mangle: fn__i64, fn__f64, etc. (matches nurlc.nu mangle_type)
        mangle_sfx = ''
        for ta_str in expr.type_args:
            if ta_str in ('i', 'u', 'f', 'b', 's', 'v'):
                llvm_ta = _llvm_type(BaseType(ta_str))
            else:
                llvm_ta = f'%{ta_str}'
            mangle_sfx += '__' + _mangle_type_str(llvm_ta)
        mangled = fn_name + mangle_sfx

        # Queue instantiation if not already scheduled
        if mangled not in self._instantiated:
            self._instantiated.add(mangled)
            concrete = _instantiate_fn(template, mangled, type_map)
            self._pending_instantiations.append((mangled, concrete))

        # Return type of this instantiation
        concrete_ret = _subst_nurl_type(template.ret_type, type_map)
        ret_t = _llvm_type(concrete_ret)

        # Generate arguments (use _last_type for type info, handles generics)
        arg_parts = []
        for arg in expr.args:
            arg_val = self._gen_expr(arg)
            arg_t   = self._last_type
            arg_parts.append(f'{arg_t} {arg_val}')
        args_str = ', '.join(arg_parts)

        if ret_t == 'void':
            self._indent(f'call void @{mangled}({args_str})')
            self._set_last_type('void')
            return 'undef'
        else:
            res = self._fresh_reg()
            self._indent(f'{res} = call {ret_t} @{mangled}({args_str})')
            self._set_last_type(ret_t)
            return res

    # ── conditional ───────────────────────────────────────────────

    def _gen_cond(self, expr: CondExpr) -> str:
        cond_reg = self._gen_expr(expr.cond)

        lbl_then = self._fresh_lbl('then')
        lbl_else = self._fresh_lbl('else')
        lbl_end  = self._fresh_lbl('end')

        self._indent(f'br i1 {cond_reg}, label %{lbl_then}, label %{lbl_else}')

        saved_ret = self._did_ret

        # ── then branch ──
        self._did_ret = False
        self._set_label(lbl_then)
        then_reg      = self._gen_expr(expr.then)
        then_ty       = self._last_type
        lbl_then_exit = self._cur_label
        then_term     = self._did_ret
        if not then_term:
            self._indent(f'br label %{lbl_end}')

        # ── else branch ──
        self._did_ret = False
        self._set_label(lbl_else)
        else_reg      = self._gen_expr(expr.else_)
        else_ty       = self._last_type
        lbl_else_exit = self._cur_label
        else_term     = self._did_ret
        if not else_term:
            self._indent(f'br label %{lbl_end}')

        self._did_ret = saved_ret

        # ── merge block ──
        self._set_label(lbl_end)

        if then_term and else_term:
            self._indent('unreachable')
            self._did_ret = True
            # result type remains what else branch set?
            # actually gen_cond in nurlc.nu doesn't call set_last_type here
            return 'undef'

        phi_ty = else_ty if then_term else then_ty
        types_ok = then_term or else_term or (then_ty == else_ty)

        if phi_ty == 'void' or not types_ok:
            self._set_last_type('void')
            return 'undef'

        res = self._fresh_reg()

        # Build phi with only live predecessors (NURL generates it even for 1 branch)
        phi_pairs = []
        if not then_term:
            phi_pairs.append(f'[ {then_reg}, %{lbl_then_exit} ]')
        if not else_term:
            phi_pairs.append(f'[ {else_reg}, %{lbl_else_exit} ]')

        self._indent(f'{res} = phi {phi_ty} {", ".join(phi_pairs)}')
        self._set_last_type(phi_ty)
        return res

    # ── loop — with phi nodes ─────────────────────────────────────

    def _gen_loop(self, expr: LoopExpr) -> str:
        lbl_check = self._fresh_lbl('loop_check')
        lbl_body  = self._fresh_lbl('loop_body')
        lbl_exit  = self._fresh_lbl('loop_exit')

        self._indent(f'br label %{lbl_check}')
        self._set_label(lbl_check)

        cond_reg = self._gen_expr(expr.cond)
        self._indent(f'br i1 {cond_reg}, label %{lbl_body}, label %{lbl_exit}')

        saved_ret = self._did_ret
        self._did_ret = False
        self._set_label(lbl_body)
        self._gen_block(expr.body)
        if not self._did_ret:
            self._indent(f'br label %{lbl_check}')
        self._set_label(lbl_exit)
        self._did_ret = saved_ret

        self._set_last_type('void')
        return 'undef'

    # ── member access ─────────────────────────────────────────────

    def _gen_member(self, expr: MemberExpr) -> str:
        obj_val  = self._gen_expr(expr.obj)
        obj_type = expr.obj.nurl_type

        # Numeric index (opt_type / slice_type / any compound)
        if isinstance(expr.field, int):
            # Should not reach here from parser — field is always str
            pass

        # Pointer receiver: *StructName → GEP + load
        if isinstance(obj_type, PtrType) and isinstance(obj_type.inner, NamedType):
            struct_name = obj_type.inner.name
            struct      = self._structs.get(struct_name)
            if struct is None:
                raise RuntimeError(f"unknown struct: {struct_name}")
            field_idx = next(
                (i for i, f in enumerate(struct.fields) if f.name == expr.field), None
            )
            if field_idx is None:
                raise RuntimeError(f"no field {expr.field!r} in {struct_name}")
            field_type = struct.fields[field_idx].type
            ft_ir      = _llvm_type(field_type)
            struct_ir  = f'%{struct_name}'
            ptr_ir     = f'{struct_ir}*'
            gep        = self._fresh_reg()
            res        = self._fresh_reg()
            self._indent(f'{gep} = getelementptr {struct_ir}, {ptr_ir} {obj_val}, i32 0, i32 {field_idx}')
            self._indent(f'{res} = load {ft_ir}, {ft_ir}* {gep}')
            self._set_last_type(ft_ir)
            return res

        # Value receiver: NamedType → extractvalue
        if not isinstance(obj_type, NamedType):
            raise RuntimeError(f"member access on non-struct: {obj_type}")

        struct   = self._structs.get(obj_type.name)
        if struct is None:
            raise RuntimeError(f"unknown struct: {obj_type.name}")

        field_idx = next(
            (i for i, f in enumerate(struct.fields) if f.name == expr.field), None
        )
        if field_idx is None:
            raise RuntimeError(f"no field {expr.field!r} in {obj_type.name}")

        field_type = struct.fields[field_idx].type
        ft_ir      = _llvm_type(field_type)
        res        = self._fresh_reg()
        struct_ir  = f'%{obj_type.name}'
        self._indent(f'{res} = extractvalue {struct_ir} {obj_val}, {field_idx}')
        self._set_last_type(ft_ir)
        return res

    # ── cast ──────────────────────────────────────────────────────

    def _gen_cast(self, expr: CastExpr) -> str:
        val  = self._gen_expr(expr.expr)
        src  = expr.expr.nurl_type
        dst  = expr.target
        sl   = _llvm_type(src) if src else 'i64'
        dl   = _llvm_type(dst)
        res  = self._fresh_reg()

        # float ↔ int casts
        if _is_float_type(src) and not _is_float_type(dst):
            self._indent(f'{res} = fptosi double {val} to {dl}')
            self._set_last_type(dl)
        elif not _is_float_type(src) and _is_float_type(dst):
            self._indent(f'{res} = sitofp {sl} {val} to double')
            self._set_last_type('double')
        elif sl == dl:
            self._set_last_type(dl)
            return val   # no-op cast
        elif sl.endswith('*') and dl == 'i64':
            # pointer → integer
            self._indent(f'{res} = ptrtoint {sl} {val} to i64')
            self._set_last_type('i64')
        elif sl == 'i64' and dl.endswith('*'):
            # integer → pointer
            self._indent(f'{res} = inttoptr i64 {val} to {dl}')
            self._set_last_type(dl)
        elif sl.endswith('*') and dl.endswith('*'):
            # pointer → pointer (bitcast)
            self._indent(f'{res} = bitcast {sl} {val} to {dl}')
            self._set_last_type(dl)
        else:
            # Integer-width conversion (e.g. i64 ↔ i8 ↔ i1). Use trunc when
            # narrowing, zext when widening — sources that need sign-
            # preserving widening will arrive with explicit signed types
            # later (i8/i16/i32 etc).
            def _bits(t: str) -> int:
                if t == 'i1':  return 1
                if t == 'i8':  return 8
                if t == 'i16': return 16
                if t == 'i32': return 32
                if t == 'i64': return 64
                return 0
            sw, dw = _bits(sl), _bits(dl)
            if sw and dw and sw != dw:
                op = 'zext' if dw > sw else 'trunc'
                self._indent(f'{res} = {op} {sl} {val} to {dl}')
            else:
                # Fallback bitcast — only valid for same-bitwidth conversions.
                self._indent(f'{res} = bitcast {sl} {val} to {dl}')
            self._set_last_type(dl)
        return res


def generate_llvm(program: Program) -> str:
    """Generate LLVM IR text from a type-checked Program."""
    return LLVMGen(program).generate()
