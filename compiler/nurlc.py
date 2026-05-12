#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# See README.md for details.
# This is bootstrap compiler
"""
nurlc — NURL compiler (reference implementation)

Usage:
  nurlc <file.nu>             compile to NUR-IR (stdout)
  nurlc --llvm <file.nu>      compile to LLVM IR (stdout)  ← for native binaries
  nurlc --lex <file.nu>       print tokens only
  nurlc --parse <file.nu>     print AST only
  nurlc --check <file.nu>     type-check only (no IR output)
  nurlc --help                show this help

To build a native binary (requires clang):
  nurlc --llvm hello.nu > hello.ll && clang -O2 hello.ll -o hello
"""

import sys
import os
import io

# Force UTF-8 output on Windows (avoids cp1252 UnicodeEncodeError).
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ('utf-8', 'utf8'):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
if sys.stderr.encoding and sys.stderr.encoding.lower() not in ('utf-8', 'utf8'):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

# Add the compiler directory to sys.path so 'src' is importable.
sys.path.insert(0, os.path.dirname(__file__))

from src.lexer    import Lexer, LexError
from src.parser   import Parser, ParseError
from src.typechecker import TypeChecker, typecheck
from src.ir_gen   import generate_ir


def _read(path: str) -> str:
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"nurlc: file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"nurlc: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_lex(path: str) -> None:
    source = _read(path)
    try:
        tokens = Lexer(source, path).tokenize()
    except LexError as e:
        print(f"lex error: {e}", file=sys.stderr)
        sys.exit(1)
    for tok in tokens:
        print(tok)


def cmd_parse(path: str) -> None:
    source = _read(path)
    try:
        tokens = Lexer(source, path).tokenize()
        program = Parser(tokens, path).parse()
    except (LexError, ParseError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    _print_ast(program)


def cmd_check(path: str) -> None:
    source = _read(path)
    try:
        tokens  = Lexer(source, path).tokenize()
        program = Parser(tokens, path).parse()
        typecheck(program)
        print("ok")
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_compile(path: str) -> None:
    source = _read(path)
    try:
        tokens  = Lexer(source, path).tokenize()
        program = Parser(tokens, path).parse()
        typecheck(program)
        ir = generate_ir(program)
        print(ir, end='')
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_llvm(path: str) -> None:
    source = _read(path)
    try:
        from src.llvm_gen import generate_llvm
        tokens  = Lexer(source, path).tokenize()
        program = Parser(tokens, path).parse()
        typecheck(program)
        ll = generate_llvm(program)
        print(ll, end='')
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


# ── AST pretty-printer ────────────────────────────────────────────

def _print_ast(node, indent: int = 0) -> None:
    pad = '  ' * indent
    name = type(node).__name__

    # Leaf nodes
    from src.ast_nodes import (
        IntLit, FloatLit, StrLit, BoolLit, IdentExpr,
        BaseType, NamedType,
    )
    if isinstance(node, IntLit):
        print(f"{pad}IntLit({node.value})")
        return
    if isinstance(node, FloatLit):
        print(f"{pad}FloatLit({node.value})")
        return
    if isinstance(node, StrLit):
        print(f"{pad}StrLit({node.value!r})")
        return
    if isinstance(node, BoolLit):
        print(f"{pad}BoolLit({node.value})")
        return
    if isinstance(node, IdentExpr):
        print(f"{pad}Ident({node.name})")
        return
    if isinstance(node, BaseType):
        print(f"{pad}BaseType({node.name})")
        return
    if isinstance(node, NamedType):
        print(f"{pad}NamedType({node.name})")
        return

    from src.ast_nodes import (
        Program, FnDecl, StructDecl, ConstDecl, ImportDecl,
        Block, LetStmt, SetStmt, ExprStmt,
        BinExpr, UnExpr, RetExpr, CallExpr, CondExpr,
        LoopExpr, MemberExpr, CastExpr, BlockExpr, Param,
        PtrType, SliceType, OptType, FnType,
    )

    if isinstance(node, Program):
        print(f"{pad}Program:")
        for d in node.decls:
            _print_ast(d, indent + 1)
        return

    if isinstance(node, FnDecl):
        print(f"{pad}FnDecl({node.name}) → {node.ret_type}")
        for p in node.params:
            print(f"{pad}  param {p.name}: {p.type}")
        _print_ast(node.body, indent + 1)
        return

    if isinstance(node, StructDecl):
        print(f"{pad}StructDecl({node.name})")
        for f in node.fields:
            print(f"{pad}  field {f.name}: {f.type}")
        return

    if isinstance(node, ConstDecl):
        print(f"{pad}ConstDecl({node.name}: {node.type})")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, ImportDecl):
        print(f"{pad}ImportDecl({node.path!r} as {node.alias})")
        return

    if isinstance(node, Block):
        print(f"{pad}Block:")
        for s in node.stmts:
            _print_ast(s, indent + 1)
        return

    if isinstance(node, LetStmt):
        print(f"{pad}LetStmt({node.name}: {node.type})")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, SetStmt):
        print(f"{pad}SetStmt({node.name})")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, ExprStmt):
        _print_ast(node.expr, indent)
        return

    if isinstance(node, BinExpr):
        print(f"{pad}BinExpr({node.op})")
        _print_ast(node.left,  indent + 1)
        _print_ast(node.right, indent + 1)
        return

    if isinstance(node, UnExpr):
        print(f"{pad}UnExpr({node.op})")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, RetExpr):
        print(f"{pad}RetExpr")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, CallExpr):
        print(f"{pad}CallExpr")
        _print_ast(node.fn, indent + 1)
        for a in node.args:
            _print_ast(a, indent + 1)
        return

    if isinstance(node, CondExpr):
        print(f"{pad}CondExpr")
        _print_ast(node.cond,  indent + 1)
        _print_ast(node.then,  indent + 1)
        _print_ast(node.else_, indent + 1)
        return

    if isinstance(node, LoopExpr):
        print(f"{pad}LoopExpr")
        _print_ast(node.cond, indent + 1)
        _print_ast(node.body, indent + 1)
        return

    if isinstance(node, MemberExpr):
        print(f"{pad}MemberExpr(.{node.field})")
        _print_ast(node.obj, indent + 1)
        return

    if isinstance(node, CastExpr):
        print(f"{pad}CastExpr(→ {node.target})")
        _print_ast(node.expr, indent + 1)
        return

    if isinstance(node, BlockExpr):
        print(f"{pad}BlockExpr:")
        for s in node.stmts:
            _print_ast(s, indent + 1)
        return

    print(f"{pad}{name}(...)")


# ── Entry point ───────────────────────────────────────────────────

def main() -> None:
    args = sys.argv[1:]

    if not args or '--help' in args or '-h' in args:
        print(__doc__)
        return

    if args[0] == '--lex' and len(args) == 2:
        cmd_lex(args[1])
    elif args[0] == '--parse' and len(args) == 2:
        cmd_parse(args[1])
    elif args[0] == '--check' and len(args) == 2:
        cmd_check(args[1])
    elif args[0] == '--llvm' and len(args) == 2:
        cmd_llvm(args[1])
    elif len(args) == 1 and not args[0].startswith('--'):
        cmd_compile(args[0])
    else:
        print(f"nurlc: unknown arguments: {' '.join(args)}", file=sys.stderr)
        print("Try 'nurlc --help'", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
