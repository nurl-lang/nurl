# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Lowering: surface AST -> core IR (AGORA-441 prototype).

Every producer form lands in a binding before anything consumes it (the
ELABORATION.md rule, applied to ALL forms): a call, a join, a match, a value
block, a literal in value position become a compiler temporary; every
consumer sees only a name or a place.  Statements are emitted in evaluation
order.  The checker (check.py) reads nothing but this IR.

Core IR
  operand  ('v', vid, path)   a place read      ('c', ty)  a constant
  rvalue   ('use', op) | ('call', fname, [op], site) | ('agg', ty, variant, [op], site)
           | ('scalar', [op]) | ('payload', op, variant, idx)
  stmt     ('let', vid, rv|None, ln)  ('assign', (vid, path), rv, ln)  ('eval', rv, ln)
           ('if', op, [stmt], [stmt], ln)   ('match', op, [(variant, [stmt])], ln)
           ('while', [stmt], op, [stmt], ln)  ('foreach', vid, op, [stmt], ln)
           ('ret', op|None, ln)  ('break', ln)  ('continue', ln)
           ('scope', [stmt], ln)  ('drop', vid, ln)
  path     a tuple of: field name | '*' (an element) | '#<variant><idx>' (a payload)
"""
from syntax import Unsupported, BASE_TYPES
from prims import PRIMS

SCALARS = {"i", "u", "f", "b", "i8", "i16", "i32", "u16", "u32", "u64", "f32",
           "u8", "v"}


class Var:
    __slots__ = ("id", "name", "ty", "kind", "line", "depth", "mut", "blk", "byref")

    def __init__(self, vid, name, ty, kind, line, depth):
        self.id, self.name, self.ty, self.kind, self.line, self.depth = vid, name, ty, kind, line, depth
        self.mut = False
        self.blk = None       # the value block's temporary, for a binding the block made
        self.byref = False    # a closure body's capture taken by pointer

    def __repr__(self):
        return f"{self.name}#{self.id}"


class FnIR:
    def __init__(self, name, line):
        self.name = name
        self.line = line
        self.params = []      # vids
        self.modes = []
        self.ret = None
        self.body = []
        self.vars = {}


class Program:
    def __init__(self):
        self.structs = {}     # name -> [(ty, fname)]
        self.enums = {}       # name -> [(variant, [ty])]
        self.sigs = {}        # user fn name -> (tparams, params, ret)
        self.fns = {}         # name -> FnIR
        self.lib_sigs = {}    # stdlib fn name -> (tparams, params, ret)


# ---------------------------------------------------------------- types
def norm(ty):
    if ty is None:
        return None
    k = ty[0]
    if k == "named":
        if ty[1] == "String":
            return ("String",)
        if ty[1] == "Vec":
            return ("vec", norm(ty[2][0])) if ty[2] else ("vec", ("tvar", "?"))
        # (with a type argument: the library's; a program's own struct of
        # that name has none, and is a struct)
        if ty[1] == "Slice" and ty[2]:
            return ("slice", norm(ty[2][0]))
        if ty[1] == "Box" and ty[2]:
            return ("box", norm(ty[2][0]))
        return ("named", ty[1], tuple(norm(a) for a in ty[2]))
    if k in ("vec", "slice", "box", "opt", "ptr"):
        return (k, norm(ty[1]))
    if k == "res":
        return ("res", norm(ty[1]), norm(ty[2]))
    return ty


def subst(ty, env):
    if ty is None:
        return None
    if ty[0] == "tvar":
        return env.get(ty[1], ty)
    if ty[0] == "named":
        if ty[1] in env and not ty[2]:
            return env[ty[1]]
        return ("named", ty[1], tuple(subst(a, env) for a in ty[2]))
    if ty[0] in ("vec", "slice", "box", "opt", "ptr"):
        return (ty[0], subst(ty[1], env))
    if ty[0] == "res":
        return ("res", subst(ty[1], env), subst(ty[2], env))
    return ty


def unify(pt, at, env, tparams):
    """Bind type variables of a parameter type pt from an argument type at."""
    if pt is None or at is None:
        return
    if pt[0] == "tvar" and pt[1] in tparams:
        env.setdefault(pt[1], at)
        return
    if pt[0] == "named" and pt[1] in tparams and not pt[2]:
        env.setdefault(pt[1], at)
        return
    if pt[0] == at[0] and pt[0] in ("vec", "slice", "box", "opt", "ptr"):
        unify(pt[1], at[1], env, tparams)


class Types:
    def __init__(self, prog):
        self.prog = prog

    def is_scalar(self, ty, seen=()):
        if ty is None:
            return True
        k = ty[0]
        if k in SCALARS or k == "ptr":
            return True
        if k == "named" and ty[1] in self.prog.enums:
            if ty[1] in seen:
                return False
            return all(all(self.is_scalar(t, seen + (ty[1],)) for t in tys)
                       for _, tys in self.prog.enums[ty[1]])
        if k == "named" and ty[1] in self.prog.structs:
            if ty[1] in seen:
                return False
            return all(self.is_scalar(t, seen + (ty[1],)) for t, _ in self.prog.structs[ty[1]])
        if k == "opt":
            return self.is_scalar(ty[1], seen)
        if k == "tvar":
            return False
        return False

    def copyable(self, ty, seen=()):
        """May a lent value of this type be copied implicitly where it escapes
        its source (ELABORATION.md rule 1)?  Owning handles yes, raw views no."""
        if self.is_scalar(ty):
            return True
        k = ty[0]
        if k == "String":
            return True
        # nurlc's own answer for a named type (a library handle's copy is a
        # share of it, a struct's a copy of each field)
        if k == "named" and ty[1] in getattr(self.prog, "clonable", ()):
            return True
        if k == "named" and ty[1] in getattr(self.prog, "unclonable", ()):
            return False
        ans = getattr(self.prog, "copy_answer", None)
        if ans and k in ("vec", "box", "opt", "res") and ty in ans:
            return ans[ty]
        if k == "res":
            return self.copyable(ty[1], seen) and self.copyable(ty[2], seen)
        if k in ("vec", "box", "opt"):
            return self.copyable(ty[1], seen)
        if k == "named" and ty[1] in seen:
            return True       # a type that holds itself: as copyable as the rest of it
        if k == "named" and ty[1] in self.prog.structs:
            return all(self.copyable(t, seen + (ty[1],)) for t, _ in self.prog.structs[ty[1]])
        if k == "named" and ty[1] in self.prog.enums:
            return all(all(self.copyable(t, seen + (ty[1],)) for t in tys)
                       for _, tys in self.prog.enums[ty[1]])
        return False

    def owning(self, ty, seen=()):
        """Does a value of this type own heap memory when it is an owner?"""
        if self.is_scalar(ty):
            return False
        k = ty[0]
        if k in ("String", "vec", "box", "slice"):
            return True
        if k == "s":
            return True   # an owned raw string (nurl_str_cat) owns; a view does not
        if k == "opt":
            return self.owning(ty[1], seen)
        if k == "named" and ty[1] in getattr(self.prog, "handle_elem", ()):
            return True       # a library handle owns its block
        if k == "named" and ty[1] not in seen:
            nseen = seen + (ty[1],)
            if ty[1] in self.prog.structs:
                return any(self.owning(t, nseen) for t, _ in self.prog.structs[ty[1]])
            if ty[1] in self.prog.enums:
                return any(any(self.owning(t, nseen) for t in tys) for _, tys in self.prog.enums[ty[1]])
        return False

    def owns_handle(self, ty, seen=()):
        """Does a value of this type hold a handle of its own - not only
        views (`s`, a slice), which a copy shares?"""
        if ty is None or self.is_scalar(ty):
            return False
        k = ty[0]
        if k in ("s", "slice"):
            return False
        if k == "opt":
            return self.owns_handle(ty[1], seen)
        if k == "res":
            return self.owns_handle(ty[1], seen) or self.owns_handle(ty[2], seen)
        if k == "named" and ty[1] not in getattr(self.prog, "handle_elem", ()) and ty[1] not in seen:
            nseen = seen + (ty[1],)
            if ty[1] in self.prog.structs:
                return any(self.owns_handle(t, nseen) for t, _ in self.prog.structs[ty[1]])
            if ty[1] in self.prog.enums:
                return any(any(self.owns_handle(t, nseen) for t in tys) for _, tys in self.prog.enums[ty[1]])
        return self.owning(ty)

    def view_capable(self, ty, seen=()):
        """Can a value of this type hold a view or a borrowed handle at all
        (a raw string, a slice, a closure, a pointer, anywhere in it)?"""
        if ty is None:
            return True
        if self.is_scalar(ty):
            return False
        k = ty[0]
        if k in ("s", "slice", "closure", "ptr"):
            return True
        if k == "String":
            return False
        if k in ("vec", "box", "opt"):
            return self.view_capable(ty[1], seen)
        if k == "res":
            return self.view_capable(ty[1], seen) or self.view_capable(ty[2], seen)
        if k == "named":
            if ty[1] in seen:
                return False
            nseen = seen + (ty[1],)
            he = getattr(self.prog, "handle_elem", {}).get(ty[1])
            if he is not None:
                return self.view_capable(he, nseen)
            if ty[1] in self.prog.structs:
                return any(self.view_capable(t, nseen) for t, _ in self.prog.structs[ty[1]])
            if ty[1] in self.prog.enums:
                return any(any(self.view_capable(t, nseen) for t in tys) for _, tys in self.prog.enums[ty[1]])
        return True

    def field(self, ty, name):
        if ty and ty[0] == "named" and ty[1] in self.prog.structs:
            for i, (fty, fname) in enumerate(self.prog.structs[ty[1]]):
                if fname == name:
                    return norm(fty), name
        return None, None

    def elem(self, ty):
        if ty and ty[0] in ("vec", "slice", "box"):
            return ty[1]
        # a library handle's payload (an Rc's, an Arc's): nurlc's type table
        if ty and ty[0] == "named":
            he = getattr(self.prog, "handle_elem", None)
            if he and ty[1] in he:
                return he[ty[1]]
        if ty and ty[0] == "String":
            return ("u",)
        return None

    def variants(self, ty):
        """[(variant, [payload types])] of an enum, option or bool."""
        if ty is None:
            return None
        if ty[0] == "opt":
            return [("T", [ty[1]]), ("F", [ty[1]])]
        if ty[0] == "res":
            return [("T", [ty[1]]), ("F", [ty[2]])]
        if ty[0] == "b":
            return [("T", []), ("F", [])]
        if ty[0] == "named" and ty[1] in self.prog.enums:
            return [(v, [norm(t) for t in tys]) for v, tys in self.prog.enums[ty[1]]]
        return None


# ------------------------------------------------------------- lowering
class Lowerer:
    def __init__(self, prog, fn_decl):
        self.prog = prog
        self.T = Types(prog)
        _, ln, name, tparams, params, ret, body, prefixes = fn_decl
        if tparams:
            raise Unsupported("generic fn def")
        if "unsafe" in prefixes or "raw" in prefixes:
            raise Unsupported("unsafe fn")
        self.decl = fn_decl
        self.fn = FnIR(name, ln)
        self.fn.ret = norm(ret)
        self.names = [{}]       # name scopes
        self.depth = 0
        self.temps = []         # stack of temp lists (per statement)
        self.site = 0
        for conv, pty, pname in params:
            v = self.new_var(pname, norm(pty), "param", ln)
            self.fn.params.append(v.id)
            self.fn.modes.append(conv)

    # -- vars -----------------------------------------------------------
    def new_var(self, name, ty, kind, line):
        vid = len(self.fn.vars)
        v = Var(vid, name, ty, kind, line, self.depth)
        self.fn.vars[vid] = v
        if kind != "temp":
            self.names[-1][name] = vid
        return v

    def lookup(self, name, line):
        for sc in reversed(self.names):
            if name in sc:
                return self.fn.vars[sc[name]]
        raise Unsupported(f"name {name} (global or function value)")

    def temp(self, ty, line, out, rv):
        v = self.new_var(f"%t{len(self.fn.vars)}", ty, "temp", line)
        out.append(("let", v.id, rv, line))
        if self.temps:
            self.temps[-1].append(v.id)
        return ("v", v.id, ())

    def next_site(self):
        self.site += 1
        return (self.fn.name, self.site)

    # -- entry ----------------------------------------------------------
    def lower(self):
        body = self.decl[6]
        out = []
        stmts = body[2]
        self.depth = 1
        self.names.append({})
        for i, st in enumerate(stmts):
            last = i == len(stmts) - 1
            if last and self.fn.ret and self.fn.ret != ("v",) and st[0] == "expr" and st[2][0] != "ret":
                self.temps.append([])
                op, ty = self.expr(st[2], out)
                out.append(("ret", op, st[1]))
                self.temps.pop()
            else:
                self.stmt(st, out)
        self.fn.body = [("scope", out, self.decl[1])]
        return self.fn

    # -- statements --------------------------------------------------------
    def block_scope(self, block, out, line):
        """A brace block in statement position: its own scope."""
        inner = []
        self.depth += 1
        self.names.append({})
        for st in block[2]:
            self.stmt(st, inner)
        self.names.pop()
        self.depth -= 1
        out.append(("scope", inner, line))

    def stmt(self, st, out):
        k, ln = st[0], st[1]
        self.temps.append([])
        if k == "let":
            _, _, mut, ty, name, e = st
            op, ety = self.expr(e, out)
            vty = norm(ty) if ty is not None else ety
            v = self.new_var(name, vty, "local", ln)
            v.mut = mut
            out.append(("let", v.id, ("use", op), ln))
        elif k == "set":
            _, _, name, e = st
            v = self.lookup(name, ln)
            op, _ = self.expr(e, out)
            out.append(("assign", (v.id, ()), ("use", op), ln))
        elif k == "setfield":
            _, _, obj, idx, e = st
            place, pty = self.place_of_member(obj, idx, out, ln)
            op, _ = self.expr(e, out)
            out.append(("assign", place, ("use", op), ln))
        elif k == "while":
            _, _, cond, body = st
            cout = []
            self.temps.append([])
            cop, _ = self.expr(cond, cout)
            for t in reversed(self.temps.pop()):
                cout.append(("drop", t, ln))
            bout = []
            self.block_scope(body, bout, ln)
            out.append(("while", cout, cop, bout, ln))
        elif k == "foreach":
            _, _, var, src, body = st
            sop, sty = self.expr(src, out)
            ety = self.T.elem(sty)
            if ety is None:
                raise Unsupported("foreach over non-slice")
            self.depth += 1
            self.names.append({})
            v = self.new_var(var, ety, "local", ln)
            bout = []
            self.block_scope(body, bout, ln)
            self.names.pop()
            self.depth -= 1
            out.append(("foreach", v.id, sop, bout, ln))
        elif k == "break":
            out.append(("break", ln))
        elif k == "continue":
            out.append(("continue", ln))
        elif k == "defer":
            raise Unsupported("defer")
        elif k == "expr":
            e = st[2]
            if e[0] == "blockexpr":
                self.block_scope(e[2], out, ln)
            elif e[0] == "cond":
                self.cond(e, out, None)
            elif e[0] == "match":
                self.match(e, out, None)
            else:
                op, _ = self.expr(e, out, stmt=True)
        else:
            raise Unsupported(f"stmt {k}")
        for t in reversed(self.temps.pop()):
            out.append(("drop", t, ln))

    # -- places ---------------------------------------------------------
    def place_of_member(self, obj, idx, out, ln):
        op, oty = self.expr(obj, out)
        if op[0] != "v":
            raise Unsupported("member of a constant")
        vid, path = op[1], op[2]
        if idx[0] == "idx_name":
            fty, fname = self.T.field(oty, idx[1])
            if fty is not None:
                return (vid, path + (fname,)), fty
            # a variable index into a slice / vec
            iv = self.lookup(idx[1], ln)
            out.append(("eval", ("scalar", [("v", iv.id, ())]), ln))
            ety = self.T.elem(oty)
            if ety is None:
                raise Unsupported("index into non-slice")
            return (vid, path + ("*",)), ety
        if idx[0] == "idx_int":
            if oty and oty[0] == "opt":
                if idx[1] == 1:
                    return (vid, path + ("#T0",)), oty[1]
                raise Unsupported("opt index 0")
            ety = self.T.elem(oty)
            if ety is None:
                raise Unsupported("int index into non-slice")
            return (vid, path + ("*",)), ety
        iop, _ = self.expr(idx[1], out)
        ety = self.T.elem(oty)
        if ety is None:
            raise Unsupported("expr index into non-slice")
        out.append(("eval", ("scalar", [iop]), ln))
        return (vid, path + ("*",)), ety

    # -- expressions ----------------------------------------------------------
    def expr(self, e, out, stmt=False):
        k, ln = e[0], e[1]
        if k == "int":
            return ("c", ("i",)), ("i",)
        if k == "float":
            return ("c", ("f",)), ("f",)
        if k == "bool":
            return ("c", ("b",)), ("b",)
        if k == "str":
            return ("c", ("s",)), ("s",)
        if k == "name":
            v = self.lookup(e[2], ln)
            return ("v", v.id, ()), v.ty
        if k in ("bin", "not", "compl"):
            ops = []
            tys = []
            for sub in e[3:] if k == "bin" else e[2:]:
                o, t = self.expr(sub, out)
                ops.append(o)
                tys.append(t)
            out.append(("eval", ("scalar", ops), ln))
            if k == "bin" and e[2] in ("<", ">", "==", "!=", "<=", ">=", "&&", "||"):
                return ("c", ("b",)), ("b",)
            return ("c", tys[-1] or ("i",)), tys[-1] or ("i",)
        if k == "ret":
            if e[2] is None:
                out.append(("ret", None, ln))
            else:
                op, _ = self.expr(e[2], out)
                out.append(("ret", op, ln))
            return ("c", ("v",)), ("v",)
        if k == "call":
            return self.call(e, out, stmt)
        if k == "member":
            place, pty = self.place_of_member(e[2], e[3], out, ln)
            return ("v", place[0], place[1]), pty
        if k == "agg":
            return self.agg(e, out)
        if k == "slicelit":
            ops = []
            for it in e[3]:
                o, _ = self.expr(it, out)
                ops.append(o)
            ty = ("slice", norm(e[2]))
            return self.temp(ty, ln, out, ("agg", ty, None, ops, self.next_site())), ty
        if k == "cast":
            ty = norm(e[2])
            op, oty = self.expr(e[3], out)
            if not self.T.is_scalar(ty):
                raise Unsupported("non-scalar cast")
            out.append(("eval", ("scalar", [op]), ln))
            return ("c", ty), ty
        if k == "cond":
            return self.cond(e, out, "value")
        if k == "match":
            return self.match(e, out, "value")
        if k == "blockexpr":
            return self.value_block(e[2], out)
        if k == "try":
            raise Unsupported("try")
        raise Unsupported(f"expr {k}")

    def value_block(self, block, out):
        """A value block: its statements run in the enclosing scope (what it
        binds is released where that scope ends, MEMORY.md §1), its names end
        at its `}`, its tail is its value - assigned, like a join's arm, to a
        temporary of the enclosing depth (a lend of the block's own locals is
        copied there, an owner of the block moves there)."""
        tv = self.join_target(None, out, block[1])
        self.names.append({})
        first = len(self.fn.vars)
        stmts = block[2]
        ty = ("v",)
        for i, st in enumerate(stmts):
            if i == len(stmts) - 1 and st[0] == "expr" and st[2][0] not in ("ret",):
                self.temps.append([])
                op, ty = self.expr(st[2], out)
                out.append(("assign", (tv.id, ()), ("use", op), block[1]))
                self.temps[-2].extend(self.temps.pop())
            else:
                self.stmt(st, out)
        for vid in range(first, len(self.fn.vars)):
            if self.fn.vars[vid].blk is None:
                self.fn.vars[vid].blk = tv.id
        self.names.pop()
        tv.ty = ty
        if ty == ("v",):
            return ("c", ("v",)), ty
        return ("v", tv.id, ()), ty

    def arm_body(self, body_expr, out, target, ln):
        """An arm of a join: its own scope; its value is assigned to target."""
        inner = []
        self.depth += 1
        self.names.append({})
        self.temps.append([])
        ty = None
        if body_expr[0] == "blockexpr":
            stmts = body_expr[2][2]
            for i, st in enumerate(stmts):
                if target is not None and i == len(stmts) - 1 and st[0] == "expr" and st[2][0] != "ret":
                    op, ty = self.expr(st[2], inner)
                    inner.append(("assign", (target, ()), ("use", op), ln))
                else:
                    self.stmt(st, inner)
        else:
            if target is not None and body_expr[0] != "ret":
                op, ty = self.expr(body_expr, inner)
                inner.append(("assign", (target, ()), ("use", op), ln))
            else:
                if body_expr[0] == "cond":
                    self.cond(body_expr, inner, None)
                elif body_expr[0] == "match":
                    self.match(body_expr, inner, None)
                else:
                    self.expr(body_expr, inner, stmt=True)
        for t in reversed(self.temps.pop()):
            inner.append(("drop", t, ln))
        self.names.pop()
        self.depth -= 1
        return [("scope", inner, ln)], ty

    def join_target(self, ty_hint, out, ln):
        v = self.new_var(f"%j{len(self.fn.vars)}", ty_hint, "temp", ln)
        out.append(("let", v.id, None, ln))
        if self.temps:
            self.temps[-1].append(v.id)
        return v

    def cond(self, e, out, mode):
        _, ln, c, a, b = e
        cop, _ = self.expr(c, out)
        if mode is None:
            ta, _ = self.arm_body(a, out, None, ln)
            tb, _ = self.arm_body(b, out, None, ln)
            out.append(("if", cop, ta, tb, ln))
            return ("c", ("v",)), ("v",)
        tv = self.join_target(None, out, ln)
        ta, tya = self.arm_body(a, out, tv.id, ln)
        tb, tyb = self.arm_body(b, out, tv.id, ln)
        tv.ty = tya if tya and tya != ("v",) else tyb
        out.append(("if", cop, ta, tb, ln))
        return ("v", tv.id, ()), tv.ty

    def match(self, e, out, mode):
        _, ln, scrut, arms = e
        sop, sty = self.expr(scrut, out)
        variants = self.T.variants(sty)
        if variants is None:
            raise Unsupported("match on non-enum")
        vmap = dict(variants)
        tv = self.join_target(None, out, ln) if mode else None
        lowered = []
        tys = []
        for pat, binds, body, aln in arms:
            if pat == "_":
                if binds:
                    raise Unsupported("_ with binds")
                vname = "_"
                ptys = []
            else:
                vname = pat
                if vname not in vmap:
                    raise Unsupported(f"pattern {pat}")
                ptys = vmap[vname]
            self.depth += 1
            self.names.append({})
            pre = []
            for i, bname in enumerate(binds):
                if i >= len(ptys):
                    raise Unsupported("payload arity")
                bv = self.new_var(bname, ptys[i], "local", aln)
                pre.append(("let", bv.id, ("payload", sop, vname, i), aln))
            arm, ty = self.arm_body(body, pre, tv.id if tv else None, aln)
            pre += arm
            tys.append(ty)
            self.names.pop()
            self.depth -= 1
            lowered.append((vname, [("scope", pre, aln)]))
        out.append(("match", sop, lowered, ln))
        if tv:
            tv.ty = next((t for t in tys if t and t != ("v",)), None)
            return ("v", tv.id, ()), tv.ty
        return ("c", ("v",)), ("v",)

    def agg(self, e, out):
        _, ln, ty, items = e
        ty = norm(ty)
        variant = None
        vs = self.T.variants(ty) if ty[0] in ("opt", "named") else None
        if ty[0] == "named" and ty[1] in self.prog.structs:
            vs = None
        if vs is not None:
            if not items or items[0][0] not in ("name", "bool"):
                raise Unsupported("enum literal without variant")
            variant = items[0][2] if items[0][0] == "name" else ("T" if items[0][2] else "F")
            items = items[1:]
        elif not (ty[0] == "named" and ty[1] in self.prog.structs):
            raise Unsupported(f"aggregate of {ty[0]}")
        ops = []
        for it in items:
            o, _ = self.expr(it, out)
            ops.append(o)
        return self.temp(ty, ln, out, ("agg", ty, variant, ops, self.next_site())), ty

    def call(self, e, out, stmt):
        _, ln, name, targs, args = e
        if name in self.prog.sigs:
            tparams, params, ret = self.prog.sigs[name]
            if tparams:
                raise Unsupported("call to generic user fn")
        elif name in PRIMS and PRIMS[name] is not None:
            sig = self.prog.lib_sigs.get(name)
            if sig is None:
                raise Unsupported(f"no signature for {name}")
            tparams, params, ret = sig
        else:
            raise Unsupported(f"call {name}")
        if len(args) != len(params):
            raise Unsupported(f"arity {name}")
        ops = []
        atys = []
        for a in args:
            o, t = self.expr(a, out)
            ops.append(o)
            atys.append(t)
        env = {}
        for tp, ta in zip(tparams, targs):
            env[tp] = norm(ta)
        for (conv, pty, _), at in zip(params, atys):
            unify(norm(pty), at, env, tparams)
        rty = subst(norm(ret), env)
        rv = ("call", name, ops, self.next_site())
        if rty is None or self.T.is_scalar(rty):
            out.append(("eval", rv, ln))
            return ("c", rty or ("v",)), rty or ("v",)
        return self.temp(rty, ln, out, rv), rty


def build_program(decls, lib_headers):
    prog = Program()
    for name, hdr in lib_headers.items():
        prog.lib_sigs[name] = hdr
    for d in decls:
        if d[0] == "struct":
            prog.structs[d[2]] = d[3]
        elif d[0] == "enum":
            prog.enums[d[2]] = d[3]
    for d in decls:
        if d[0] == "fn":
            if d[2] in prog.sigs:
                raise Unsupported("duplicate fn")
            prog.sigs[d[2]] = (d[3], d[4], d[5])
    for d in decls:
        if d[0] == "fn":
            prog.fns[d[2]] = Lowerer(prog, d).lower()
    return prog
