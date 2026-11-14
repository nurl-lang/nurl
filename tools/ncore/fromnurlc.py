# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The core IR as nurlc prints it (`nurlc --emit-core`), read into the form
check.py checks (AGORA-858).

nurlc builds the IR as a by-product of its walk (compiler/nurlc.nu, "Core
IR"): this module runs it on a program and parses what it prints. Nothing
here looks at the source: every construct the language has reaches the
checker the way the compiler lowered it.

  fn    name  ret  nparams  line  file  flags  template
  v     id  kind  depth  flags  line  block  name  type   (one per variable)
  <statements, one a line>
  endfn
  ty    type  class  drops[c]  base  A n targ…  F n (name type)…  V n (variant npay ptype…)…
  virt  callee  impl…
"""
import os
import subprocess

from syntax import Unsupported
from lower import FnIR, Program, Var

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

SCALAR_NAMES = {"i64": "i", "i1": "b", "double": "f", "float": "f32", "void": "v", "": "v",
                "i8": "u", "u8": "u", "i16": "i16", "i32": "i32", "u16": "u16", "u32": "u32",
                "u64": "u64"}
# Library handles over one payload, and the ones whose copies share it.
SHARED_HANDLES = {"Rc", "Arc", "Shared"}
HANDLES_OF_ONE = SHARED_HANDLES | {"Channel", "Locked", "RwLocked", "Deque", "Set"}
KINDS = {0: "param", 1: "local", 2: "temp", 3: "param"}


class TypeInfo:
    __slots__ = ("name", "cls", "drops", "clone", "udrop", "share", "tshare", "base", "targs", "fields", "variants")


def nurlc_binary():
    return os.environ.get("NURLC") or os.path.join(ROOT, "build", "nurlc")


def emit_core(path):
    """nurlc's core IR of the program at `path`, and what it could not lower.
    With NCORE_CACHE set to a directory, what nurlc printed is kept there
    and read back (delete the directory when nurlc changes)."""
    cache = os.environ.get("NCORE_CACHE")
    key = None
    if cache:
        os.makedirs(cache, exist_ok=True)
        key = os.path.join(cache, os.path.basename(path))
        if os.path.exists(key + ".rc"):
            with open(key + ".core", encoding="utf-8") as f:
                out = f.read()
            with open(key + ".err", encoding="utf-8") as f:
                err = f.read()
            with open(key + ".rc") as f:
                rc = int(f.read())
            return out, [l for l in err.splitlines() if l.startswith("core-gap\t")], rc, err
    r = subprocess.run([nurlc_binary(), "--emit-core", os.path.abspath(path)], cwd=ROOT,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if key:
        with open(key + ".core", "w", encoding="utf-8") as f:
            f.write(r.stdout)
        with open(key + ".err", "w", encoding="utf-8") as f:
            f.write(r.stderr)
        with open(key + ".rc", "w") as f:
            f.write(str(r.returncode))
    gaps = [l for l in r.stderr.splitlines() if l.startswith("core-gap\t")]
    return r.stdout, gaps, r.returncode, r.stderr


class Reader:
    def __init__(self, text):
        self.prog = Program()
        self.prog.fn_flags = {}        # name -> flags (bit 0: raw memory allowed)
        self.prog.fn_tmpl = {}         # name -> the generic it is an instance of
        self.prog.fn_file = {}
        self.prog.clonable = set()     # named types nurlc can copy a value of
        self.prog.unclonable = set()   # …and the ones it cannot
        self.prog.udrop = set()        # named types whose drop is a use of the views they hold (§2.14)
        self.prog.handle_elem = {}     # a one-payload handle type -> its payload's type
        self.prog.shared = set()       # …the ones whose copies share the payload
        self.prog.thread_share = set() # handles a thread's closure captures as a share of its own (§6.5)
        self.prog.copy_answer = {}     # a Vec / Box / option / result type -> can a copy of it be made
        self.prog.arcs = set()         # …and the ones other threads may hold a copy of
        self.prog.virt = {}            # a `dyn` method's virtual callee -> the impls it may run
        self.prog.walk_sums = {}       # a function -> the answers the walk's summaries hold for it (`sum` lines)
        self.types = {}                # type string -> TypeInfo
        self.conv_memo = {}
        self.raw_fns = []
        self.all_fns = self.prog.fns
        self.parse(text)
        for fn in self.raw_fns:
            self.finish_fn(fn)

    # -- parsing ---------------------------------------------------------
    def parse(self, text):
        cur = None
        for line in text.split("\n"):
            if not line:
                continue
            if line.startswith("fn\t"):
                f = line.split("\t")
                cur = {"name": f[1], "ret": f[2], "nparams": int(f[3]), "line": int(f[4]),
                       "file": f[5], "flags": int(f[6]) if len(f) > 6 else 0,
                       "tmpl": f[7] if len(f) > 7 else "", "vars": [], "stmts": []}
            elif line.startswith("v\t") and cur is not None:
                f = line.split("\t")
                cur["vars"].append((int(f[1]), int(f[2]), int(f[3]), int(f[4]), int(f[5]), int(f[6]),
                                    f[7], f[8] if len(f) > 8 else ""))
            elif line == "endfn":
                self.raw_fns.append(cur)
                cur = None
            elif line.startswith("ty\t"):
                self.parse_type(line.split("\t"))
            elif line.startswith("virt\t"):
                f = line.split("\t")
                self.prog.virt[f[1]] = f[2:]
            elif line.startswith("sum\t"):
                f = line.split("\t")
                self.prog.walk_sums[f[1]] = dict(kv.split("=", 1) for kv in f[3:])
            elif cur is not None:
                cur["stmts"].append(line)

    def parse_type(self, f):
        t = TypeInfo()
        t.name, t.cls, t.drops, t.base = f[1], int(f[2]), f[3].startswith("1"), f[4]
        t.clone = "c" in f[3]              # a copy of a value of it can be made
        t.udrop = "d" in f[3]              # its drop runs the program's code, which may read its views
        t.share = "h" in f[3]              # its copy is a share of one object
        t.tshare = "t" in f[3]             # …that two threads may use at once
        i = 5
        assert f[i] == "A"
        n = int(f[i + 1])
        t.targs = f[i + 2:i + 2 + n]
        i += 2 + n
        assert f[i] == "F"
        n = int(f[i + 1])
        t.fields = [(f[i + 2 + 2 * k], f[i + 3 + 2 * k]) for k in range(n)]
        i += 2 + 2 * n
        assert f[i] == "V"
        n = int(f[i + 1])
        i += 2
        t.variants = []
        for _ in range(n):
            vname, pn = f[i], int(f[i + 1])
            t.variants.append((vname, f[i + 2:i + 2 + pn]))
            i += 2 + pn
        self.types[t.name] = t

    # -- types -----------------------------------------------------------
    def conv(self, t):
        """A nurlc type as check.py's type tuple."""
        if t in self.conv_memo:
            return self.conv_memo[t]
        self.conv_memo[t] = ("named", t, ())        # a recursive type meets itself
        r = self.conv1(t)
        self.conv_memo[t] = r
        info = self.types.get(t)
        if info is not None and r[0] in ("vec", "box", "opt", "res"):
            # nurlc's own answer to "can a copy of it be made" (a Vec of
            # views is copied view by view)
            self.prog.copy_answer[r] = info.clone
        return r

    def conv1(self, t):
        if t in SCALAR_NAMES:
            return (SCALAR_NAMES[t],)
        if t == "i8*":
            return ("s",)
        if t.endswith("*"):
            return ("ptr", self.conv(t[:-1]))
        if t.startswith("<") or t.startswith("["):
            return ("i",)
        info = self.types.get(t)
        if t.startswith("{"):
            fs = [ft for _, ft in info.fields] if info else []
            if len(fs) == 2 and fs[0] == "i1":
                return ("opt", self.conv(fs[1]))
            if len(fs) == 3 and fs[0] == "i1":
                return ("res", self.conv(fs[1]), self.conv(fs[2]))
            if len(fs) == 2 and fs[0].endswith("*") and fs[1] == "i64":
                return ("slice", self.conv(fs[0][:-1]))
            return ("closure", t)
        if t.startswith("%"):
            name = t[1:]
            if info is None:
                return ("named", name, ())
            if info.base == "String" and not info.targs:
                return ("String",)
            if info.base == "Vec" and len(info.targs) == 1:
                return ("vec", self.conv(info.targs[0]))
            if info.base == "Box" and len(info.targs) == 1:
                return ("box", self.conv(info.targs[0]))
            if info.base == "Slice" and len(info.targs) == 1:
                return ("slice", self.conv(info.targs[0]))
            # nurlc's own answer: a library handle's copy is a share of it, a
            # struct's a copy of each field - and a value with a `% Drop` of
            # its own and no clone has none
            if getattr(info, "udrop", False):
                self.prog.udrop.add(name)
            if getattr(info, "tshare", False):
                self.prog.thread_share.add(name)
            if getattr(info, "clone", False):
                self.prog.clonable.add(name)
            else:
                self.prog.unclonable.add(name)
            # (a handle over one payload: the ones listed, and any other
            # library handle with one type argument - a guard, a pool)
            if len(info.targs) == 1 and (info.base in HANDLES_OF_ONE or info.cls == 0):
                # a handle over one payload: `*` is the payload
                self.prog.handle_elem[name] = self.conv(info.targs[0])
                if info.base in SHARED_HANDLES:
                    self.prog.shared.add(name)
                if info.base == "Arc":
                    self.prog.arcs.add(name)
                return ("named", name, ())
            if info.variants:
                self.prog.enums[name] = [(v, list(pts)) for v, pts in info.variants]
                self.prog.enums[name] = [(v, [self.conv(p) for p in pts]) for v, pts in info.variants]
            elif info.fields:
                self.prog.structs[name] = [(("named", name, ()), fn) for fn, _ in info.fields]
                self.prog.structs[name] = [(self.conv(ft), fn) for fn, ft in info.fields]
            return ("named", name, ())
        return ("i",)

    # -- one function ----------------------------------------------------
    def operand(self, tok, fn):
        if tok == "c":
            return ("c", ("i",))
        if tok == "-":
            return None
        if tok == "?":
            raise Unsupported("operand nurlc did not name")
        parts = tok.split("/")
        root = parts[0]
        if root.startswith("g:"):
            # a module global: safe code reads only one set at start, which
            # nothing replaces or releases - a value with nothing to track
            return ("c", ("i",))
        vid = int(root[1:])
        ty = fn.vars[vid].ty
        path = []
        for p in parts[1:]:
            if p.startswith("#"):
                idx = int(p[1:])
                if ty is not None and ty[0] == "opt":
                    if idx != 1:
                        # (its flag: a number)
                        return ("c", ("i",))
                    p = "#T0"
                    ty = ty[1]
                elif ty is not None and ty[0] == "res":
                    if idx == 1:
                        p, ty = "#T0", ty[1]
                    elif idx == 2:
                        p, ty = "#F0", ty[2]
                    else:
                        return ("c", ("i",))
                elif ty is not None and ty[0] in ("slice", "vec"):
                    # (an element named by its position: an element)
                    p = "*"
                    ty = self.T.elem(ty)
                else:
                    raise Unsupported("positional member of " + (ty[0] if ty else "?"))
            elif p == "*":
                ty = self.T.elem(ty)
            else:
                if ty is not None and ty[0] == "box":
                    # (a field read through a Box is a field of what it holds)
                    path.append("*")
                    ty = self.T.elem(ty)
                nty, _ = self.T.field(ty, p)
                if nty is None and ty is not None and ty[0] in ("slice", "String", "vec") and p in ("length", "len", "cap"):
                    # a slice's length, a handle's size: a number
                    return ("c", ("i",))
                if nty is None and ty is not None and ty[0] not in ("named",):
                    raise Unsupported(f"field {p} of {ty[0]}")
                ty = nty
            path.append(p)
        return ("v", vid, tuple(path))

    def rvalue(self, toks, rest_ty, fn, site):
        k = toks[0]
        if k == "none":
            return None
        if k == "use":
            return ("use", self.operand(toks[1], fn))
        if k == "call":
            n = int(toks[2])
            callee = self.all_fns.get(toks[1])
            if callee is not None and len(callee.params) != n:
                raise Unsupported(f"arity: {toks[1]} takes {len(callee.params)}, the call has {n}")
            return ("call", toks[1], [self.operand(t, fn) for t in toks[3:3 + n]], site)
        if k == "agg":
            n = int(toks[2])
            variant = None if toks[1] == "-" else toks[1]
            ty = self.conv(rest_ty)
            return ("agg", ty, variant, [self.operand(t, fn) for t in toks[3:3 + n]], site)
        if k == "scalar":
            n = int(toks[1])
            return ("scalar", [self.operand(t, fn) for t in toks[2:2 + n]])
        if k == "payload":
            return ("payload", self.operand(toks[1], fn), toks[2], int(toks[3]))
        if k == "closure":
            n = int(toks[2])
            return ("closure", toks[1], [self.operand(t, fn) for t in toks[3:3 + n]], site)
        if k == "callind":
            n = int(toks[1])
            return ("callind", [self.operand(t, fn) for t in toks[2:2 + n]], site)
        if k == "opaque":
            raise Unsupported(f"construct nurlc did not lower (token {toks[1]})")
        raise Unsupported("rvalue " + k)

    def finish_fn(self, raw):
        from lower import Types
        self.T = Types(self.prog)
        fn = FnIR(raw["name"], raw["line"])
        fn.ncap = 0
        fn.is_closure = raw["name"].startswith("__closure_")
        fn.ret = self.conv(raw["ret"])
        for vid, kind, depth, flags, line, blk, name, ty in raw["vars"]:
            v = Var(vid, name or f"%t{vid}", self.conv(ty) if ty else None, KINDS.get(kind, "local"),
                    line, depth)
            v.mut = bool(flags & 1)
            v.blk = blk if blk >= 0 else None
            v.byref = bool(flags & 8)      # a capture taken by pointer
            fn.vars[vid] = v
            if kind == 3:
                # a closure body's capture: a parameter the closure itself hands it
                fn.params.append(vid)
                fn.modes.append("cap")
                fn.ncap += 1
            elif kind == 0:
                fn.params.append(vid)
                fn.modes.append("inout" if flags & 2 else "sink" if flags & 4 else "in")
        fn.raw = raw
        self.prog.fns[fn.name] = fn
        self.prog.fn_flags[fn.name] = raw["flags"]
        self.prog.fn_tmpl[fn.name] = raw["tmpl"]
        self.prog.fn_file[fn.name] = raw["file"]

    def lower_body(self, fn):
        """The function's statements as check.py's tuples; raises Unsupported
        where the IR holds something the checker has no rule for yet."""
        from lower import Types
        self.T = Types(self.prog)
        lines = fn.raw["stmts"]
        self.pos = 0
        self.ln = fn.line
        self.site = 0
        body = self.block(lines, fn, ("endfn",))
        fn.body = body
        return fn

    def next_site(self, fn):
        self.site += 1
        return (fn.name, self.site)

    def block(self, lines, fn, stop):
        """Statements up to (not including) a line in `stop`."""
        out = []
        while self.pos < len(lines):
            line = lines[self.pos]
            head = line.split(" ", 1)[0]
            if head in stop:
                return out
            self.pos += 1
            if "\t" in line:
                line, rest_ty = line.split("\t", 1)
            else:
                rest_ty = None
            toks = line.split(" ")
            k = toks[0]
            ln = self.ln
            if k == "line":
                self.ln = int(toks[1])
            elif k == "nop":
                pass
            elif k == "let":
                vid = int(toks[1])
                out.append(("let", vid, self.rvalue(toks[2:], rest_ty, fn, self.next_site(fn)), ln))
            elif k == "assign":
                rv = self.rvalue(toks[2:], rest_ty, fn, self.next_site(fn))
                if toks[1] == "c":
                    # a store into a global of numbers: nothing to track
                    out.append(("eval", rv, ln))
                elif toks[1].startswith("g:"):
                    # a store into a module global: what it is given outlives
                    # every frame
                    out.append(("gstore", toks[1][2:].split("/")[0], rv, ln))
                else:
                    op = self.operand(toks[1], fn)
                    out.append(("assign", (op[1], op[2]), rv, ln))
            elif k == "eval":
                out.append(("eval", self.rvalue(toks[1:], rest_ty, fn, self.next_site(fn)), ln))
            elif k == "drop":
                out.append(("drop", int(toks[1]), ln))
            elif k == "ret":
                out.append(("ret", self.operand(toks[1], fn), ln))
            elif k == "break":
                out.append(("break", ln))
            elif k == "continue":
                out.append(("continue", ln))
            elif k == "defer":
                inner = self.block(lines, fn, ("end",))
                self.pos += 1
                out.append(("defer", inner, ln))
            elif k == "scope":
                inner = self.block(lines, fn, ("end",))
                self.pos += 1
                out.append(("scope", inner, ln))
            elif k == "if":
                cop = self.operand(toks[1], fn)
                a = self.block(lines, fn, ("else", "end"))
                b = []
                if lines[self.pos] == "else":
                    self.pos += 1
                    b = self.block(lines, fn, ("end",))
                self.pos += 1
                out.append(("if", cop, a, b, ln))
            elif k == "match":
                sop = self.operand(toks[1], fn)
                arms = []
                while lines[self.pos].startswith("arm "):
                    vname = lines[self.pos][4:]
                    self.pos += 1
                    arms.append((vname, self.block(lines, fn, ("arm", "end"))))
                self.pos += 1
                out.append(("match", sop, arms, ln))
            elif k == "loop":
                cond = self.block(lines, fn, ("loopcond",))
                cop = self.operand(lines[self.pos].split(" ")[1], fn)
                self.pos += 1
                body = self.block(lines, fn, ("end",))
                self.pos += 1
                out.append(("while", cond, cop, body, ln))
            elif k == "foreach":
                vid = int(toks[1])
                sop = self.operand(toks[2], fn)
                body = self.block(lines, fn, ("end",))
                self.pos += 1
                out.append(("foreach", vid, sop, body, ln))
            else:
                raise Unsupported("statement " + k)
        return out


def read_program(path):
    """The program at `path` as nurlc lowers it: (Reader, gaps, exit code)."""
    text, gaps, rc, err = emit_core(path)
    return Reader(text), gaps, rc, err
