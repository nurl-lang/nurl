# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""NURL surface syntax: lexer and parser for the subset the core-IR prototype
lowers (AGORA-441).  The parser is total over the grammar it knows and raises
Unsupported on anything else, so a probe outside the subset is reported as
SKIP, never guessed at.

The AST is plain tuples: (kind, line, ...fields).  Kinds are listed at
each parse_* function.
"""
import re


class Unsupported(Exception):
    pass


class ParseError(Exception):
    pass


BASE_TYPES = {"i", "u", "f", "b", "s", "v", "i8", "i16", "i32", "u16", "u32",
              "u64", "f32", "u8"}
BIN_OPS = {"+", "-", "*", "/", "%", "<", ">", "==", "!=", "<=", ">=", "<<",
           ">>", "&", "|", "^^", "&&", "||"}
MULTI = ["...", "→", "==", "!=", "<=", ">=", "<<", ">>", "??", "^^", "&&",
         "||", "::"]
SINGLE = set("(){}[]?!*#@:=~^.;$&%|<>+-/\\")


def lex(src):
    """Tokens as (text, kind, line).  kind: id, int, float, str, op."""
    toks = []
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "`":
            j = i + 1
            while j < n and src[j] != "`":
                if src[j] == "\\":
                    j += 1
                j += 1
            toks.append((src[i + 1:j], "str", line))
            line += src[i:j].count("\n")
            i = j + 1
            continue
        if c.isdigit() or (c == "-" and i + 1 < n and src[i + 1].isdigit()
                           and (not toks or toks[-1][1] == "op"
                                and toks[-1][0] not in (")", "]"))):
            m = re.match(r"-?(0x[0-9a-fA-F_]+|0b[01_]+|[0-9_]+(\.[0-9_]+([eE][-+]?[0-9]+)?)?)", src[i:])
            t = m.group(0)
            toks.append((t, "float" if "." in t else "int", line))
            i += len(t)
            continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*", src[i:])
            t = m.group(0)
            toks.append((t.replace("::", "__"), "id", line))
            i += len(t)
            continue
        for mo in MULTI:
            if src.startswith(mo, i):
                toks.append((mo, "op", line))
                i += len(mo)
                break
        else:
            if c in SINGLE:
                toks.append((c, "op", line))
                i += 1
            else:
                # any other byte (e.g. unicode) - treat as op token
                toks.append((c, "op", line))
                i += 1
    toks.append(("<eof>", "eof", line))
    return toks


class Parser:
    def __init__(self, toks, type_names, generic_types=None):
        self.t = toks
        self.p = 0
        self.type_names = type_names          # struct / enum names
        self.generic_types = generic_types or set()

    # -- token helpers ------------------------------------------------
    def peek(self, k=0):
        return self.t[min(self.p + k, len(self.t) - 1)]

    def tok(self, k=0):
        return self.peek(k)[0]

    def kind(self, k=0):
        return self.peek(k)[1]

    def line(self):
        return self.peek()[2]

    def next(self):
        t = self.t[self.p]
        self.p += 1
        return t

    def expect(self, text):
        t = self.next()
        if t[0] != text:
            raise ParseError(f"line {t[2]}: expected {text!r}, got {t[0]!r}")
        return t

    def at_close(self, k):
        return self.tok(k) == "}" and self.kind(k) == "op"

    def at(self, text):
        return self.tok() == text and self.kind() in ("op", "id")

    # -- types ----------------------------------------------------------
    def is_type_start(self, k=0):
        t, kd = self.tok(k), self.kind(k)
        if kd == "id":
            return t in BASE_TYPES or t in self.type_names
        return t in ("(", "[", "?", "??", "!", "*", "%")

    def parse_type(self):
        t, kd, ln = self.next()
        if kd == "id":
            if t in BASE_TYPES:
                return (t,)
            if t in self.type_names:
                return ("named", t, ())
            if t == "T":  # type variable T
                return ("tvar", "T")
            # type variable of a generic declaration or unknown name
            return ("tvar", t)
        if t == "?":
            return ("opt", self.parse_type())
        if t == "??":
            return ("opt", ("opt", self.parse_type()))
        if t == "!":
            a = self.parse_type()
            b = self.parse_type()
            return ("res", a, b)
        if t == "[":
            return ("slice", self.parse_type())
        if t == "*":
            return ("ptr", self.parse_type())
        if t == "%":
            raise Unsupported("dyn type")
        if t == "(":
            if self.at("@"):
                raise Unsupported("fn type")
            name, nk, _ = self.next()
            args = []
            while not self.at(")"):
                args.append(self.parse_type())
            self.expect(")")
            if name == "Vec":
                return ("vec", args[0])
            if name == "Slice":
                return ("slice", args[0])
            if name == "Box":
                return ("box", args[0])
            if name in self.type_names or name in self.generic_types:
                return ("named", name, tuple(args))
            raise Unsupported(f"generic type {name}")
        raise ParseError(f"line {ln}: bad type token {t!r}")

    # -- declarations ---------------------------------------------------
    def parse_program(self):
        decls = []
        while self.kind() != "eof":
            d = self.parse_decl()
            if d is not None:
                decls.append(d)
        return decls

    def parse_decl(self):
        ln = self.line()
        prefixes = set()
        while self.tok() in ("pub", "unsafe", "raw", "inline", "simd") and self.kind() == "id":
            pf = self.next()[0]
            prefixes.add(pf)
            if pf == "simd" and self.tok() == "v4":
                self.next()
        t = self.tok()
        if t == "$":
            self.next()
            path = self.next()[0]
            if self.kind() == "id" and self.peek()[2] == ln:
                raise Unsupported("aliased import")
            return ("import", ln, path)
        if t == "&":
            raise Unsupported("ffi decl")
        if t == "%":
            raise Unsupported("trait/impl")
        if t == "@":
            return self.parse_fn(prefixes)
        if t == ":":
            self.next()
            if self.at("|"):
                self.next()
                name = self.next()[0]
                self.expect("{")
                variants = []
                while not self.at("}"):
                    vname = self.next()[0]
                    tys = []
                    while self.is_type_start():
                        tys.append(self.parse_type())
                    variants.append((vname, tys))
                self.expect("}")
                return ("enum", ln, name, variants)
            if self.at("~"):
                raise Unsupported("mutable global")
            name = self.tok()
            if self.kind() == "id" and name not in BASE_TYPES and self.tok(1) in ("{", "["):
                self.next()
                tparams = []
                if self.at("["):
                    self.next()
                    while not self.at("]"):
                        tparams.append(self.next()[0])
                    self.next()
                    raise Unsupported("generic struct")
                self.expect("{")
                fields = []
                while not self.at("}"):
                    ty = self.parse_type()
                    fname = None
                    if self.kind() == "id" and not self.is_type_start():
                        fname = self.next()[0]
                    elif self.kind() == "id" and self.tok() in BASE_TYPES and (
                            self.at_close(1) or self.is_type_start(1)):
                        fname = self.next()[0]
                    fields.append((ty, fname))
                self.expect("}")
                return ("struct", ln, name, fields)
            raise Unsupported("global const")
        raise ParseError(f"line {ln}: unexpected top-level token {t!r}")

    def _looks_variant(self, p):
        return False

    def parse_fn(self, prefixes):
        ln = self.line()
        self.expect("@")
        name = self.next()[0]
        tparams = []
        if self.at("["):
            self.next()
            while not self.at("]"):
                tparams.append(self.next()[0])
                while self.at(":"):
                    self.next()
                    self.next()
            self.next()
        params = []
        saved = self.type_names
        if tparams:
            self.type_names = set(saved) | set(tparams)
        while not self.at("→"):
            conv = "in"
            if self.tok() in ("in", "inout", "sink") and self.kind() == "id" and (self.is_type_start(1) or self.tok(1) in ("(", "[")):
                conv = self.next()[0]
            ty = self.parse_type()
            pname = self.next()[0]
            if self.at("="):
                raise Unsupported("default parameter")
            params.append((conv, ty, pname))
        self.expect("→")
        ret = self.parse_type()
        if not self.at("{"):
            self.type_names = saved
            return ("fnhdr", ln, name, tparams, params, ret, prefixes)
        body = self.parse_block()
        self.type_names = saved
        return ("fn", ln, name, tparams, params, ret, body, prefixes)

    # -- statements -------------------------------------------------------
    def parse_block(self):
        ln = self.line()
        self.expect("{")
        stmts = []
        while not self.at("}"):
            stmts.append(self.parse_stmt())
        self.expect("}")
        return ("block", ln, stmts)

    def parse_stmt(self):
        ln = self.line()
        t, kd = self.tok(), self.kind()
        if t == ":" and kd == "op":
            self.next()
            mut = False
            if self.at("~"):
                self.next()
                mut = True
            ty = None
            # `: name expr` (inferred) vs `: Type name expr`
            if not (self.kind() == "id" and self.tok() not in BASE_TYPES and self.tok() not in self.type_names):
                ty = self.parse_type()
            name = self.next()[0]
            e = self.parse_expr()
            return ("let", ln, mut, ty, name, e)
        if t == "=" and kd == "op":
            self.next()
            if self.at("."):
                self.next()
                obj = self.parse_expr()
                idx = self.parse_index()
                e = self.parse_expr()
                return ("setfield", ln, obj, idx, e)
            name = self.next()[0]
            e = self.parse_expr()
            return ("set", ln, name, e)
        if t == ";" and kd == "op":
            self.next()
            return ("defer", ln, self.parse_block())
        if t == "break" and kd == "id":
            self.next()
            return ("break", ln)
        if t == "continue" and kd == "id":
            self.next()
            return ("continue", ln)
        if t == "~" and kd == "op":
            # foreach: ~ IDENT IDENT … | ~ IDENT . …
            if self.kind(1) == "id" and (self.kind(2) == "id" or self.tok(2) in (".", "(")) and self.tok(1) not in BASE_TYPES:
                if self.tok(2) == "(" :
                    # `~ x ( f … ) {` is a foreach over a call result
                    pass
                self.next()
                var = self.next()[0]
                src = self.parse_expr()
                body = self.parse_block()
                return ("foreach", ln, var, src, body)
            self.next()
            cond = self.parse_expr()
            if self.at("{"):
                body = self.parse_block()
                return ("while", ln, cond, body)
            return ("expr", ln, ("compl", ln, cond))
        return ("expr", ln, self.parse_expr())

    def parse_index(self):
        if self.kind() == "id" and self.tok() not in ("T", "F"):
            # field name, or a variable index (resolved later)
            return ("idx_name", self.next()[0])
        if self.kind() == "int":
            return ("idx_int", int(self.next()[0], 0))
        return ("idx_expr", self.parse_expr())

    # -- expressions ------------------------------------------------------
    def parse_expr(self):
        ln = self.line()
        t, kd, _ = self.peek()
        if kd == "int":
            self.next()
            return ("int", ln, int(t.replace("_", ""), 0))
        if kd == "float":
            self.next()
            return ("float", ln, t)
        if kd == "str":
            self.next()
            return ("str", ln, t)
        if kd == "id":
            if t in ("T", "F"):
                self.next()
                return ("bool", ln, t == "T")
            if t == "Z":
                raise Unsupported("sizeof")
            if t in ("break", "continue"):
                raise ParseError(f"line {ln}: {t} in expression")
            self.next()
            return ("name", ln, t)
        if kd == "eof":
            raise ParseError("unexpected eof")
        if t in BIN_OPS:
            self.next()
            a = self.parse_expr()
            b = self.parse_expr()
            return ("bin", ln, t, a, b)
        if t == "!":
            self.next()
            return ("not", ln, self.parse_expr())
        if t == "^":
            self.next()
            if self.at("}"):
                return ("ret", ln, None)
            return ("ret", ln, self.parse_expr())
        if t == "~":
            self.next()
            return ("compl", ln, self.parse_expr())
        if t == "\\":
            # closure: \ param* → … ; try: \ expr
            k = 1
            if self.tok(1) == "→" or self.is_type_start(1) and self.kind(1) != "op" or self.tok(1) in ("inout", "sink"):
                raise Unsupported("closure")
            if self.tok(1) == "(" and self.tok(2) not in ("@",) and self.kind(2) == "id" and self.tok(2) in ("Vec", "Slice", "Box"):
                raise Unsupported("closure")
            self.next()
            return ("try", ln, self.parse_expr())
        if t == "@":
            self.next()
            ty = self.parse_type()
            self.expect("{")
            items = []
            while not self.at("}"):
                items.append(self.parse_expr())
            self.expect("}")
            return ("agg", ln, ty, items)
        if t == "[":
            self.next()
            ty = self.parse_type()
            self.expect("|")
            items = []
            while not self.at("]"):
                items.append(self.parse_expr())
            self.expect("]")
            return ("slicelit", ln, ty, items)
        if t == ".":
            self.next()
            obj = self.parse_expr()
            idx = self.parse_index()
            return ("member", ln, obj, idx)
        if t == "#":
            self.next()
            ty = self.parse_type()
            e = self.parse_expr()
            return ("cast", ln, ty, e)
        if t == "?":
            self.next()
            c = self.parse_expr()
            a = self.parse_expr()
            b = self.parse_expr()
            return ("cond", ln, c, a, b)
        if t == "??":
            self.next()
            if self.at("{"):
                raise Unsupported("select")
            scrut = self.parse_expr()
            self.expect("{")
            arms = []
            while not self.at("}"):
                arms.append(self.parse_arm())
            self.expect("}")
            return ("match", ln, scrut, arms)
        if t == "{":
            b = self.parse_block()
            return ("blockexpr", ln, b)
        if t == "(":
            self.next()
            name, nk, _ = self.next()
            if name == "dyn":
                raise Unsupported("dyn")
            if nk != "id":
                raise ParseError(f"line {ln}: call head {name!r}")
            targs = []
            if self.at("[") and self.is_type_start(1):
                self.next()
                while not self.at("]"):
                    targs.append(self.parse_type())
                self.next()
            args = []
            while not self.at(")"):
                if self.kind() == "id" and self.tok(1) == ":" and self.kind(1) == "op":
                    raise Unsupported("keyword argument")
                args.append(self.parse_expr())
            self.expect(")")
            return ("call", ln, name, targs, args)
        raise ParseError(f"line {ln}: unexpected token {t!r}")

    def parse_arm(self):
        ln = self.line()
        pat = self.next()[0]
        if self.at("|") and self.kind() == "op":
            raise Unsupported("or-pattern")
        binds = []
        while not self.at("→") and not self.at("?"):
            b = self.next()
            if b[1] == "int":
                raise Unsupported("literal pattern payload")
            binds.append(b[0])
        if self.at("?"):
            raise Unsupported("match guard")
        self.expect("→")
        if self.tok() in ("=", ":", ";") and self.kind() == "op" or self.tok() in ("break", "continue") and self.kind() == "id":
            st = self.parse_stmt()
            body = ("blockexpr", ln, ("block", ln, [st]))
        else:
            body = self.parse_expr()
        return (pat, binds, body, ln)


def scan_type_names(toks):
    """Struct and enum names declared at top level (`: Name {` / `: | Name {`)."""
    names = set()
    gen = set()
    depth = 0
    for i, (t, k, _) in enumerate(toks):
        if t in ("{",) and k == "op":
            depth += 1
        elif t == "}" and k == "op":
            depth -= 1
        elif depth == 0 and t == ":" and k == "op":
            a = toks[i + 1]
            if a[0] == "|":
                names.add(toks[i + 2][0])
            elif a[1] == "id" and toks[i + 2][0] in ("{", "["):
                names.add(a[0])
                if toks[i + 2][0] == "[":
                    gen.add(a[0])
    return names, gen
