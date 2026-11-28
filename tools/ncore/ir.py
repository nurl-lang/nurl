# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The core IR as check.py reads it, and the program it belongs to
(AGORA-441 prototype). nurlc builds the IR (`nurlc --emit-core`,
docs/dev/CORE_IR.md); fromnurlc.py reads it into these forms. This reader
has no front end of its own: a second one, mirroring nurlc's, went in
AGORA-1046 (the owner's rule: no Python mirror of a NURL component).

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


class Unsupported(Exception):
    """A construct the checker does not model: the probe is skipped and named."""


class ParseError(Exception):
    """nurlc's core IR not in the form fromnurlc.py reads."""


SCALARS = {"i", "u", "f", "b", "i8", "i16", "i32", "u16", "u32", "u64", "f32",
           "u8", "v"}


class Var:
    __slots__ = ("id", "name", "ty", "kind", "line", "depth", "mut", "blk", "byref", "carried",
                 "handon", "slot", "cpcopy", "taken", "agglend", "envown", "unlinked")

    def __init__(self, vid, name, ty, kind, line, depth):
        self.id, self.name, self.ty, self.kind, self.line, self.depth = vid, name, ty, kind, line, depth
        self.mut = False
        self.blk = None       # the value block's temporary, for a binding the block made
        self.byref = False    # a closure body's capture taken by pointer
        self.carried = False  # a temporary of a join's arm that lives to the end of the join's statement
        self.handon = False   # the literal a `\` try hands its failure on in (nurlc's IR only)
        self.slot = False     # a call's option temporary whose payload codegen takes out of its slot (nurlc's IR only)
        self.unlinked = False  # a binding of a call's result codegen linked to no owner (nurlc's IR only, AGORA-1005)
        self.cpcopy = False   # a value codegen copied into a by-pointer capture where its call lent (nurlc's IR only, agora #884)
        self.taken = False    # a capture the closure's env takes over (nurlc's IR only: capture flag 4, agora #868, #887)
        self.agglend = False  # a returned literal codegen built without copying a field it was given lent (nurlc's IR only, agora #907)
        self.envown = False   # a handle capture a returned closure's env owns (nurlc's IR only: capture flag 2048, AGORA-978); the engine does not ask it

    def __repr__(self):
        return f"{self.name}#{self.id}"


class FnIR:
    def __init__(self, name, line):
        self.name = name
        self.line = line
        self.params = []      # vids
        self.modes = []
        self.ret = None
        # (the result is an owned slice `[T`, not a view `( Slice T )`: both
        # are ("slice", T); a closure's owned one is copied where it lends,
        # check.clo_slice_copies)
        self.ret_owned_slice = False
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


INF = float("inf")


class Types:
    def __init__(self, prog):
        self.prog = prog
        self._memo = {}
        self._low = INF

    def _named(self, q, name, seen, cyc, walk):
        """A named type's answer to the question q, asked inside of the
        named types `seen`: one met again answers `cyc`.  Where no type met
        again inside it was one of `seen` (the lowest place on the stack a
        type met again was at, `_low`, is its own or deeper), the answer is
        the one asked from outside, and kept: each named type is walked
        once per question, not once per path to it (a struct of eight
        fields eight deep was 8^8 walks).  An answer kept that way is the
        one the question asked inside reaches as well: the question is
        whether a leaf answering it is reachable from where it was asked,
        and a cycle through one of `seen` is reached from that type too."""
        if name in seen:
            i = seen.index(name)
            if i < self._low:
                self._low = i
            return cyc
        memo = self._memo.setdefault(q, {})
        if name in memo:
            return memo[name]
        was, self._low = self._low, INF
        r = walk(seen + (name,))
        d = len(seen)
        if self._low >= d:
            memo[name] = r
            self._low = was
        else:
            self._low = min(was, self._low)
        if not seen:
            self._low = was
        return r

    def is_scalar(self, ty, seen=()):
        if ty is None:
            return True
        k = ty[0]
        if k in SCALARS or k == "ptr":
            return True
        if k == "named" and ty[1] in self.prog.enums:
            return self._named("scalar", ty[1], seen, False, lambda ns: all(
                all(self.is_scalar(t, ns) for t in tys) for _, tys in self.prog.enums[ty[1]]))
        if k == "named" and ty[1] in self.prog.structs:
            return self._named("scalar", ty[1], seen, False, lambda ns: all(
                self.is_scalar(t, ns) for t, _ in self.prog.structs[ty[1]]))
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
        # (a type that holds itself: as copyable as the rest of it)
        if k == "named" and ty[1] in self.prog.structs:
            return self._named("copyable", ty[1], seen, True, lambda ns: all(
                self.copyable(t, ns) for t, _ in self.prog.structs[ty[1]]))
        if k == "named" and ty[1] in self.prog.enums:
            return self._named("copyable", ty[1], seen, True, lambda ns: all(
                all(self.copyable(t, ns) for t in tys) for _, tys in self.prog.enums[ty[1]]))
        if k == "named" and ty[1] in seen:
            return True
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
        if k == "res":
            # (a result whose success or error payload owns memory: as
            # `owns_handle` already reads it)
            return any(t is not None and self.owning(t, seen) for t in ty[1:3])
        if k == "named" and ty[1] in getattr(self.prog, "nodrop", ()):
            return False      # nurlc's own answer: it has nothing to release
        if k == "named" and ty[1] in getattr(self.prog, "handle_elem", ()):
            return True       # a library handle owns its block
        if k == "named" and ty[1] in self.prog.structs:
            return self._named("owning", ty[1], seen, False, lambda ns: any(
                self.owning(t, ns) for t, _ in self.prog.structs[ty[1]]))
        if k == "named" and ty[1] in self.prog.enums:
            return self._named("owning", ty[1], seen, False, lambda ns: any(
                any(self.owning(t, ns) for t in tys) for _, tys in self.prog.enums[ty[1]]))
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
        # (a type met again answers as an owner does)
        if k == "named" and ty[1] not in getattr(self.prog, "handle_elem", ()):
            cyc = self.owning(ty) if ty[1] in seen else False
            if ty[1] in self.prog.structs:
                return self._named("owns_handle", ty[1], seen, cyc, lambda ns: any(
                    self.owns_handle(t, ns) for t, _ in self.prog.structs[ty[1]]))
            if ty[1] in self.prog.enums:
                return self._named("owns_handle", ty[1], seen, cyc, lambda ns: any(
                    any(self.owns_handle(t, ns) for t in tys) for _, tys in self.prog.enums[ty[1]]))
        return self.owning(ty)

    def has_udrop(self, ty):
        """Does a value of this type run, where it is released, a destructor
        that may read the views it holds?  nurlc's own answer for a named
        type (the `d` flag: a `% Drop` of the program's own anywhere in it,
        a library handle asked by its type arguments), followed through the
        types this reader spells out."""
        if ty is None or self.is_scalar(ty):
            return False
        k = ty[0]
        if k in ("vec", "box", "opt"):
            return self.has_udrop(ty[1])
        if k == "res":
            return self.has_udrop(ty[1]) or self.has_udrop(ty[2])
        return k == "named" and ty[1] in getattr(self.prog, "udrop", ())

    def shared_in(self, ty, seen=()):
        """The shared handle types (an Rc, an Arc, a program handle whose
        copy is a share) a value of this type may reach."""
        if ty is None or self.is_scalar(ty):
            return set()
        k = ty[0]
        if k in ("vec", "box", "opt", "slice"):
            return self.shared_in(ty[1], seen)
        if k == "res":
            return self.shared_in(ty[1], seen) | self.shared_in(ty[2], seen)
        if k != "named":
            return set()
        return set(self._named("shared_in", ty[1], seen, frozenset(), lambda ns: self._shared_named(ty[1], ns)))

    def _shared_named(self, name, seen):
        out = {name} if name in getattr(self.prog, "shared", ()) else set()
        he = getattr(self.prog, "handle_elem", {}).get(name)
        if he is not None:
            return frozenset(out | self.shared_in(he, seen))
        for t, _ in self.prog.structs.get(name, ()):
            out |= self.shared_in(t, seen)
        for _, tys in self.prog.enums.get(name, ()):
            for t in tys:
                out |= self.shared_in(t, seen)
        return frozenset(out)

    def view_capable(self, ty, seen=()):
        """Can a value of this type hold a view or a borrowed handle at all
        (a raw string, a slice, a closure, a pointer, anywhere in it)?"""
        if ty is None:
            return True
        # (the parts first, a number last: is_scalar counts a pointer - and
        # a struct or option of pointers - as a number, but what one points
        # at may be anyone's storage; nurlc's __ty_holds_view asks for a
        # pointer anywhere in the value)
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
            return self._named("view_capable", ty[1], seen, False, lambda ns: self._view_capable_named(ty[1], ns))
        if self.is_scalar(ty):
            return False
        return True

    def _view_capable_named(self, name, nseen):
        he = getattr(self.prog, "handle_elem", {}).get(name)
        if he is not None:
            return self.view_capable(he, nseen)
        if name in self.prog.structs:
            return any(self.view_capable(t, nseen) for t, _ in self.prog.structs[name])
        if name in self.prog.enums:
            return any(any(self.view_capable(t, nseen) for t in tys) for _, tys in self.prog.enums[name])
        return True

    def field(self, ty, name):
        if ty and ty[0] == "named" and ty[1] in self.prog.structs:
            for i, (fty, fname) in enumerate(self.prog.structs[ty[1]]):
                if fname == name:
                    return norm(fty), name
        return None, None

    def at(self, ty, path):
        """The type of the place `path` inside a value of type `ty`."""
        for p in path:
            if ty is None:
                return None
            if p == "*":
                ty = self.elem(ty)
            elif p.startswith("#"):
                vs = self.variants(ty)
                if not vs:
                    return None
                var, idx = p[1:-1], int(p[-1])
                d = dict(vs)
                ty = d[var][idx] if var in d and idx < len(d[var]) else None
            else:
                ty, _ = self.field(ty, p)
        return ty

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
        # an enum of the program's whose container payloads all hold one
        # element type (`Json`: `JArr ( Vec Json )`, `JObj ( Vec Json )`):
        # `*` is an element of one of them - what a walk down it reaches
        if ty and ty[0] == "named" and ty[1] in self.prog.enums:
            es = set()
            for _, tys in self.prog.enums[ty[1]]:
                for t in tys:
                    t = norm(t)
                    if t and t[0] in ("vec", "slice", "box"):
                        es.add(t[1])
            if len(es) == 1:
                return es.pop()
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
