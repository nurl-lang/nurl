# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The one checker over the core IR (AGORA-441 prototype).

State per program point:
  vals[vid] = AV(own, loans, alias, held)
    own    'O' owner, 'P' parameter root, 'L' lent (owns nothing),
           'N' nothing to track (scalar, static string), 'M' moved,
           'X' maybe moved, 'U' not yet assigned, 'D' released
    loans  the loans this value needs valid (its handle / view of a place)
    alias  the places this value is a handle or view of
    held   (path, loan): the views stored inside the value, by where they
           sit in it (a field, '*' the elements, '#T0' a payload)
  dead   loans killed so far (a value needing one is dangling)

A loan is (place, kind): 'handle' (a copy of the place's handle) or 'view'
(a pointer into the place's own buffer).  An effect on a place kills loans by
formal/A2's Eff.kills, extended from bindings to places.

Function summaries are those of prims.py, inferred for program functions by a
fixpoint over the whole program: definition order plays no part."""
from prims import PRIMS
from lower import Types


class CheckError(Exception):
    pass


def prefix(p, q):
    return len(p) <= len(q) and q[:len(p)] == p


def hsub(held, path):
    """What a value holds at its sub-path `path`, re-rooted there."""
    out = set()
    n = len(path)
    for hp, l in held:
        if prefix(path, hp):
            out.add((hp[n:], l))
        elif prefix(hp, path):
            out.add(((), l))
    return frozenset(out)


def hroot(held, path):
    return frozenset((path + hp, l) for hp, l in held)


def hloans(held):
    return frozenset(l for _, l in held)


def hfrom(loans, path=()):
    return frozenset((path, l) for l in loans)


class AV:
    __slots__ = ("own", "loans", "alias", "held")

    def __init__(self, own, loans=frozenset(), alias=frozenset(), held=frozenset()):
        self.own, self.loans, self.alias, self.held = own, frozenset(loans), frozenset(alias), frozenset(held)

    def key(self):
        return (self.own, self.loans, self.alias, self.held)

    def __repr__(self):
        return f"AV({self.own},{set(self.loans)},{set(self.alias)},{set(self.held)})"


NONE = AV("N")


def join_own(a, b):
    if a == b:
        return a
    s = {a, b}
    if "U" in s:
        return (s - {"U"}).pop()
    if s <= {"O", "L", "N"}:
        return "O" if "O" in s else "L"   # an owner on one path: dropped by flag
    if s & {"M", "X", "D"}:
        return "X"
    return "O" if "O" in s else a


class State:
    __slots__ = ("vals", "dead", "bottom")

    def __init__(self, vals=None, dead=frozenset(), bottom=False):
        self.vals = dict(vals or {})
        self.dead = frozenset(dead)
        self.bottom = bottom

    def copy(self):
        return State(self.vals, self.dead, self.bottom)

    def key(self):
        return (self.bottom, self.dead, tuple(sorted((k, v.key()) for k, v in self.vals.items())))


def join(a, b):
    if a.bottom:
        return b.copy()
    if b.bottom:
        return a.copy()
    vals = {}
    for k in set(a.vals) | set(b.vals):
        x, y = a.vals.get(k), b.vals.get(k)
        if x is None or y is None:
            vals[k] = x or y
            continue
        vals[k] = AV(join_own(x.own, y.own), x.loans | y.loans, x.alias | y.alias, x.held | y.held)
    return State(vals, a.dead | b.dead)


VIEW_TYPES = ("s", "slice")


class FnCheck:
    """One function's abstract run, under the current summaries."""

    def __init__(self, prog, fn, summaries, final):
        self.prog = prog
        self.fn = fn
        self.T = Types(prog)
        self.summ = summaries
        self.final = final
        self.errors = []
        self.loans = {}          # loan id -> (place, kind)
        self.pidx = {vid: i for i, vid in enumerate(fn.params)}
        self.s_effects = set()
        self.s_consumes = set()
        self.s_elems = set()
        self.rets = []
        self.exits = []
        self.loop_stack = []

    # -- names / errors -----------------------------------------------------
    def err(self, line, msg):
        if self.final:
            self.errors.append((self.fn.name, line, msg))

    def vname(self, vid):
        return self.fn.vars[vid].name

    def pname(self, place):
        vid, path = place
        out = self.vname(vid)
        for p in path:
            out += "[*]" if p == "*" else (p if p.startswith("#") else "." + p)
        return out

    # -- types of places ----------------------------------------------------------
    def ty_of_place(self, place):
        vid, path = place
        ty = self.fn.vars[vid].ty
        for p in path:
            if ty is None:
                return None
            if p == "*":
                ty = self.T.elem(ty)
            elif p.startswith("#"):
                vs = self.T.variants(ty)
                if not vs:
                    return None
                var, idx = p[1:-1], int(p[-1])
                d = dict(vs)
                ty = d[var][idx] if var in d and idx < len(d[var]) else None
            else:
                ty, _ = self.T.field(ty, p)
        return ty

    def holds_views(self, ty):
        if ty is None:
            return True
        e = self.T.elem(ty)
        if e is None:
            return False
        return e[0] in VIEW_TYPES or (not self.T.is_scalar(e) and not self.T.owning(e))

    # -- loans ----------------------------------------------------------------
    def loan(self, st, site, place, kind):
        lid = (site, place, kind)
        if lid in st.dead:
            # made again at the same site in a later round of a loop: whatever
            # still holds the old one keeps a dead loan; the new one is live
            stale = ("stale", lid)
            sw = lambda l: stale if l == lid else l
            for vid, av in list(st.vals.items()):
                if lid in av.loans or lid in hloans(av.held):
                    st.vals[vid] = AV(av.own, {sw(l) for l in av.loans}, av.alias,
                                      {(p, sw(l)) for p, l in av.held})
            st.dead = (st.dead - {lid}) | {stale}
            self.loans[stale] = (place, kind)
        self.loans[lid] = (place, kind)
        return lid

    def kills(self, eff, p, lid):
        (q, k) = self.loans[lid]
        if q[0] != p[0]:
            return False
        pp, qp = p[1], q[1]
        if pp == qp:
            if eff == "replace" or k == "view":
                return True
            return self.holds_views(self.ty_of_place(q))
        if prefix(pp, qp):           # the effect is on an ancestor of the loan's place
            rest = qp[len(pp):]
            if eff == "replace":
                return True
            if eff == "drop":
                return any(r == "*" or r.startswith("#") for r in rest)
            return False
        if prefix(qp, pp):           # the effect is inside the loan's place
            rest = pp[len(qp):]
            if k == "handle" and self.holds_views(self.ty_of_place(q)):
                return True
            if k == "handle" and eff == "replace" and "*" not in rest:
                return True
            return False
        return False

    def all_loans(self, st):
        live = set()
        for v in st.vals.values():
            live |= v.loans | hloans(v.held)
        return live

    def effect(self, st, place, eff, line, depth=0):
        vid, path = place
        av = st.vals.get(vid)
        if av is None or depth > 8:
            return
        if av.own == "L":
            for a in av.alias:
                self.effect(st, (a[0], a[1] + path), eff, line, depth + 1)
            return
        if vid in self.pidx:
            self.s_effects.add((self.pidx[vid], path[:3], eff))
        killed = {l for l in self.loans if l not in st.dead and self.kills(eff, place, l)}
        if killed:
            st.dead = st.dead | killed
        # what the place held is gone with what the effect released
        if eff in ("drop", "replace") and av.held:
            keep = set()
            for hp, l in av.held:
                if eff == "replace" and prefix(path, hp):
                    continue
                if eff == "drop" and prefix(path, hp) and len(hp) > len(path):
                    continue
                keep.add((hp, l))
            st.vals[vid] = AV(av.own, av.loans, av.alias, keep)

    def would_kill(self, st, place, eff, loans, depth=0):
        vid, path = place
        av = st.vals.get(vid)
        if av is None or depth > 8:
            return set()
        if av.own == "L":
            out = set()
            for a in av.alias:
                out |= self.would_kill(st, (a[0], a[1] + path), eff, loans, depth + 1)
            return out
        return {l for l in loans if l not in st.dead and l in self.loans and self.kills(eff, place, l)}

    # -- reads ------------------------------------------------------------------
    def check_live(self, st, av, line, what, held=False):
        dead = (av.loans | (hloans(av.held) if held else frozenset())) & st.dead
        if dead:
            lid = sorted(dead, key=repr)[0]
            place, kind = self.loans[lid]
            self.err(line, f"{what} uses a {kind} of {self.pname(place)}, which was changed or released")
            return False
        return True

    def view_value(self, held_here):
        """A view-typed value read out of where it is held: its loans are the
        loans held there, and it views their places."""
        loans = hloans(held_here)
        if not loans:
            return NONE
        alias = {self.loans[l][0] for l in loans if l in self.loans}
        return AV("L", loans, alias, frozenset())

    def read(self, st, op, line, site, what="value"):
        if op[0] == "c":
            return NONE
        _, vid, path = op
        av = st.vals.get(vid)
        if av is None:
            return NONE
        name = self.vname(vid)
        if av.own in ("M", "X"):
            self.err(line, f"{name} is used after it was moved")
            return NONE
        if av.own == "D":
            self.err(line, f"{name} is used after it was released")
            return NONE
        if av.own == "U":
            return NONE
        self.check_live(st, av, line, name)
        ty = self.ty_of_place((vid, path))
        if ty is not None and self.T.is_scalar(ty):
            if path:
                self.check_live(st, AV("N", held=hsub(av.held, path)), line, name, held=True)
            return NONE
        sub = hsub(av.held, path) if path else av.held
        if av.own in ("O", "P"):
            if not path:
                return AV(av.own, av.loans, {(vid, ())}, av.held)
            if ty is not None and ty[0] in VIEW_TYPES:
                v = self.view_value(sub)
                self.check_live(st, v, line, self.pname((vid, path)))
                return v
            lid = self.loan(st, site, (vid, path), "handle")
            return AV("L", {lid}, {(vid, path)}, sub)
        if av.own == "L":
            if not path:
                return av
            if ty is not None and ty[0] in VIEW_TYPES and sub:
                v = self.view_value(sub)
                self.check_live(st, v, line, self.pname((vid, path)))
                return AV("L", v.loans | av.loans, v.alias, frozenset())
            alias = {(a[0], a[1] + path) for a in av.alias}
            loans = set(av.loans)
            for a in alias:
                loans.add(self.loan(st, site, a, "handle"))
            return AV("L", loans, alias, sub)
        return av

    def local_depth(self, av):
        d = 0
        for lid in av.loans | hloans(av.held):
            if lid not in self.loans:
                continue
            place = self.loans[lid][0]
            v = self.fn.vars[place[0]]
            if v.kind != "param":
                d = max(d, v.depth)
        for a in av.alias:
            v = self.fn.vars[a[0]]
            if v.kind != "param":
                d = max(d, v.depth)
        return d

    def move_out(self, st, vid, line):
        src = st.vals[vid]
        if src.own == "P":
            self.s_consumes.add(self.pidx[vid])
        self.effect(st, (vid, ()), "replace", line)
        st.vals[vid] = AV("M")
        return AV("O", src.loans, frozenset(), src.held)

    def refers_to_block(self, av, blk):
        for lid in av.loans:
            if lid in self.loans and self.fn.vars[self.loans[lid][0][0]].blk == blk:
                return True
        return any(self.fn.vars[a[0]].blk == blk for a in av.alias)

    def transfer(self, st, op, line, site, dest_depth, dest_ty, what, copy_ok=False, is_ret=False,
                 lend_owner=lambda vid: False, dest_vid=None):
        """A value handed to a new holder (a let, `=`, a return, a field): an
        owner moves; a lend is copied with its loans, or - where it would
        outlive a local it borrows from - deep-copied (a join's value, a
        return) or refused."""
        av = self.read(st, op, line, site, what)
        if op[0] == "v" and not op[2] and av.own in ("O", "P"):
            vid = op[1]
            src = st.vals[vid]
            vty = self.fn.vars[vid].ty
            raw = vty is not None and vty[0] in VIEW_TYPES
            to_view = dest_ty is not None and dest_ty[0] == "s" and vty is not None and vty[0] != "s"
            if to_view:
                av = AV("L", {self.loan(st, site, (vid, ()), "view")}, {(vid, ())}, frozenset())
            elif src.own == "P" or (self.fn.vars[vid].kind != "temp" and ((raw and not is_ret) or lend_owner(vid))):
                # a parameter is lent to its new name (the caller owns it); an
                # owned raw string or slice is viewed, not moved
                av = AV("L", {self.loan(st, site, (vid, ()), "view" if raw else "handle")}, {(vid, ())}, src.held)
            else:
                av = self.move_out(st, vid, line)
        own_block = dest_vid is not None and self.refers_to_block(av, dest_vid)
        if av.own == "L" and (own_block or self.local_depth(AV("L", av.loans, av.alias)) > dest_depth):
            if copy_ok and dest_ty is not None and self.T.copyable(dest_ty) and not self.T.is_scalar(dest_ty):
                return AV("O")
            if own_block:
                return av
            if copy_ok and not is_ret:
                # a join's or block's value that cannot be copied stays a
                # lend: if what it borrows ends first, its use is the error
                return av
            self.err(line, f"{what}: a view of a value released before its holder escapes")
        if av.held and self.local_depth(AV("N", held=av.held)) > dest_depth and not (copy_ok and not is_ret):
            self.err(line, f"{what}: holds a view of a value released before it")
        return av

    # -- calls -----------------------------------------------------------------
    def summary(self, name):
        if name in self.summ:
            return self.summ[name]
        if PRIMS.get(name) is not None:
            return PRIMS[name]
        # a generic's instance answers as its template does
        tmpl = getattr(self.prog, "fn_tmpl", {}).get(name)
        if tmpl and PRIMS.get(tmpl) is not None:
            return PRIMS[tmpl]
        from syntax import Unsupported
        raise Unsupported(f"no summary for {tmpl or name}")

    def apply_call(self, st, rv, line):
        _, name, ops, site = rv
        sm = self.summary(name)
        avs = []
        for i, op in enumerate(ops):
            av = self.read(st, op, line, (site, i), f"argument {i + 1} of {name}")
            if i in sm["elems"] and av.own != "N":
                self.check_live(st, av, line, f"argument {i + 1} of {name}", held=True)
                for a in av.alias:
                    if a[0] in self.pidx:
                        self.s_elems.add(self.pidx[a[0]])
            avs.append(av)
        # a call may not change what another of its arguments views (A2: a
        # call's arguments are frozen for its duration)
        for (k, path, eff) in sm["effects"]:
            if k >= len(ops) or ops[k][0] != "v":
                continue
            place = (ops[k][1], ops[k][2] + tuple(path))
            for m, av in enumerate(avs):
                if m != k and self.would_kill(st, place, eff, av.loans | hloans(av.held)):
                    self.err(line, f"{name}: argument {m + 1} views what the call changes through argument {k + 1}")
                elif m == k and self.would_kill(st, place, eff, hloans(av.held)):
                    # A2: an argument is frozen for the call - a part of it may
                    # not view what the call changes in another part
                    self.err(line, f"{name}: a part of argument {k + 1} views what the call changes in it")
        # consumed arguments
        for k in sm["consumes"]:
            if k >= len(ops):
                continue
            op = ops[k]
            if op[0] == "v" and not op[2]:
                for m, av in enumerate(avs):
                    if m != k and (any(a[0] == op[1] for a in av.alias) or
                                   any(self.loans.get(l, ((None,), None))[0][0] == op[1] for l in av.loans)):
                        self.err(line, f"{name} takes {self.vname(op[1])} while argument {m + 1} still reads it")
                cur = st.vals.get(op[1])
                if cur and cur.own in ("O", "P"):
                    self.move_out(st, op[1], line)
                    continue
            if avs[k].own == "L":
                ty = self.ty_of_place((op[1], op[2])) if op[0] == "v" else None
                if ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES:
                    if not self.take_payload(st, avs[k], line):
                        self.err(line, f"{name} takes a borrowed value (clone it)")
        # effects
        for (k, path, eff) in sm["effects"]:
            if k < len(ops) and ops[k][0] == "v":
                self.effect(st, (ops[k][1], ops[k][2] + tuple(path)), eff, line)
        # stores into arguments
        for (j, dpath, k, path, kind) in sm["stores"]:
            if j >= len(ops) or k >= len(ops) or ops[j][0] != "v":
                continue
            src = avs[k]
            dpath = tuple(dpath)
            if kind == "value":
                op = ops[k]
                if src.own in ("O", "P") and op[0] == "v" and not op[2]:
                    moved = self.move_out(st, op[1], line)
                    add = hroot(moved.held, dpath)
                elif src.own == "L":
                    ty = self.ty_of_place((op[1], op[2])) if op[0] == "v" else None
                    if ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES and self.T.copyable(ty):
                        add = frozenset()          # a lend stored as an owner is copied
                    else:
                        add = hfrom(src.loans, dpath) | hroot(src.held, dpath)
                else:
                    add = hroot(src.held, dpath)
            elif kind == "held":
                add = hroot(hsub(src.held, tuple(path)), dpath)
            else:
                add = set(hfrom(src.loans, dpath))
                for a in src.alias:
                    add.add((dpath, self.loan(st, (site, "s", j, k, dpath), (a[0], a[1] + tuple(path)), kind)))
            self.store_into(st, (ops[j][1], ops[j][2] + dpath), add, already_rooted=True, base=ops[j][2])
        # the result
        held = set()
        for (dpath, k, path, kind) in sm["rholds"]:
            if k >= len(avs):
                continue
            dpath = tuple(dpath)
            if kind == "held":
                held |= hroot(hsub(avs[k].held, tuple(path)), dpath)
            else:
                held |= hfrom(avs[k].loans, dpath)
                for a in avs[k].alias:
                    held.add((dpath, self.loan(st, (site, "r", k, dpath), (a[0], a[1] + tuple(path)), kind)))
        if sm["res"] == "own":
            return AV("O", (), (), held)
        if sm["res"] == "lent":
            loans, alias = set(), set()
            for (k, path, kind) in sm["lends"]:
                if k >= len(avs) or avs[k].own == "N":
                    continue
                av = avs[k]
                loans |= av.loans
                for a in av.alias:
                    pl = (a[0], a[1] + tuple(path))
                    alias.add(pl)
                    loans.add(self.loan(st, (site, "l", k), pl, kind))
                held |= hsub(av.held, tuple(path))
            if not loans and not alias:
                return AV("N", (), (), held)
            return AV("L", loans, alias, held)
        return NONE

    def handover(self, st, place):
        """A store replacing a place whose old value a binding reads hands
        that old value over to the binding (MEMORY.md §7.6, agora #265):
        it owns it from here on."""
        for vid, av in list(st.vals.items()):
            if av.own == "L" and av.alias == frozenset({place}) and self.fn.vars[vid].kind != "temp":
                ty = self.fn.vars[vid].ty
                if ty is None or ty[0] in VIEW_TYPES:
                    continue
                keep = {l for l in av.loans if self.loans.get(l, (None,))[0] != place}
                st.vals[vid] = AV("O", keep, frozenset(), av.held)

    def take_payload(self, st, av, line):
        """A payload bound out of an owner local's `??` may be taken: the
        owner is then (maybe) moved."""
        if len(av.alias) != 1:
            return False
        vid, path = next(iter(av.alias))
        root = st.vals.get(vid)
        if root is None or root.own not in ("O", "P") or not path or path[-1] == "*":
            return False
        self.effect(st, (vid, path), "replace", line)
        if root.own == "P":
            self.s_consumes.add(self.pidx[vid])
        if "*" not in path:
            st.vals[vid] = AV("X")
        return True

    def store_into(self, st, place, add, depth=0, already_rooted=False, base=()):
        """Record loans now held inside the value at place.  `add` entries are
        rooted at the value's root var when already_rooted (paths include the
        place's own path minus base)."""
        vid, path = place
        av = st.vals.get(vid)
        if av is None or depth > 8:
            return
        if already_rooted:
            add = hroot(add, base)
        else:
            add = hroot(add, path)
        if av.own == "L":
            # through a handle: what its places hold
            for a in av.alias:
                self.store_into(st, (a[0], a[1]), frozenset((hp, l) for hp, l in add), depth + 1, True, a[1])
            return
        st.vals[vid] = AV(av.own, av.loans, av.alias, av.held | frozenset(add))

    # -- rvalues ---------------------------------------------------------------
    def rvalue(self, st, rv, line, dest_depth, dest_ty, what, copy_ok=False, lend_owner=lambda vid: False,
               dest_vid=None):
        k = rv[0]
        if k == "use":
            return self.transfer(st, rv[1], line, ("use", id(rv)), dest_depth, dest_ty, what, copy_ok=copy_ok,
                                 lend_owner=lend_owner, dest_vid=dest_vid)
        if k == "call":
            av = self.apply_call(st, rv, line)
            if av.own == "L" and self.local_depth(AV("L", av.loans, av.alias)) > dest_depth:
                if copy_ok and dest_ty is not None and self.T.copyable(dest_ty) and not self.T.is_scalar(dest_ty):
                    return AV("O")
                self.err(line, f"{what}: a view of a value released before its holder escapes")
            return av
        if k == "agg":
            _, ty, variant, ops, site = rv
            names = self.agg_paths(ty, variant, len(ops))
            held = set()
            for i, op in enumerate(ops):
                fty = self.ty_of_field(ty, variant, i)
                av = self.transfer(st, op, line, (site, i), dest_depth, fty, f"field {i + 1}")
                fp = (names[i],)
                if av.own == "L":
                    if fty is not None and self.T.owning(fty) and fty[0] not in VIEW_TYPES and self.T.copyable(fty):
                        continue   # a lend stored into an owning field is copied
                    held |= hfrom(av.loans, fp)
                held |= hroot(av.held, fp)
            return AV("O", (), (), held)
        if k == "scalar":
            for i, op in enumerate(rv[1]):
                self.read(st, op, line, ("sc", id(rv), i))
            return NONE
        if k == "payload":
            _, op, variant, idx = rv
            av = self.read(st, op, line, ("pl", id(rv)), "matched value")
            if av.own == "N":
                return NONE
            tag = f"#{variant}{idx}"
            sub = hsub(av.held, (tag,))
            pty = self.ty_of_field(self.fn.vars[op[1]].ty if op[0] == "v" and not op[2] else None, variant, idx)
            if op[0] == "v" and not op[2] and self.fn.vars[op[1]].kind == "temp" and av.own == "O":
                return AV("O", (), (), sub)
            if pty is not None and pty[0] in VIEW_TYPES:
                v = self.view_value(sub)
                return AV("L", v.loans | av.loans, v.alias, frozenset()) if v.own == "L" else NONE
            loans, alias = set(av.loans), set()
            for a in av.alias:
                pl = (a[0], a[1] + (tag,))
                alias.add(pl)
                loans.add(self.loan(st, ("pl", id(rv), pl), pl, "handle"))
            return AV("L", loans, alias, sub)
        raise CheckError(f"rvalue {k}")

    def agg_paths(self, ty, variant, n):
        if variant is not None:
            return [f"#{variant}{i}" for i in range(n)]
        if ty and ty[0] == "named" and ty[1] in self.prog.structs:
            fs = self.prog.structs[ty[1]]
            return [fs[i][1] or str(i) for i in range(min(n, len(fs)))] + [str(i) for i in range(len(fs), n)]
        return ["*"] * n

    def ty_of_field(self, ty, variant, i):
        if ty is None:
            return None
        if variant is not None:
            vs = self.T.variants(ty)
            d = dict(vs or [])
            return d[variant][i] if variant in d and i < len(d[variant]) else None
        if ty[0] == "named" and ty[1] in self.prog.structs:
            fs = self.prog.structs[ty[1]]
            from lower import norm
            return norm(fs[i][0]) if i < len(fs) else None
        return self.T.elem(ty)

    # -- statements --------------------------------------------------------------
    def run(self, st, stmts):
        for s in stmts:
            if st.bottom:
                break
            st = self.stmt(st, s)
        return st

    def scope_end(self, st, stmts, line):
        if st.bottom:
            return st
        declared = [s[1] for s in stmts if s[0] == "let"]
        for vid in reversed(declared):
            av = st.vals.get(vid)
            if av is None:
                continue
            if av.own == "O":
                self.effect(st, (vid, ()), "replace", line)
            if av.own != "M":
                st.vals[vid] = AV("D")
        return st

    def stmt(self, st, s):
        k = s[0]
        if k == "let":
            _, vid, rv, ln = s
            v = self.fn.vars[vid]
            if rv is None:
                st.vals[vid] = AV("U")
            else:
                # `: ~ T c x` is a cursor: it borrows the owner x
                st.vals[vid] = self.rvalue(st, rv, ln, v.depth, v.ty, v.name,
                                           lend_owner=(lambda x: True) if v.mut else (lambda x: False))
            return st
        if k == "assign":
            _, (vid, path), rv, ln = s
            v = self.fn.vars[vid]
            cur = st.vals.get(vid)
            ddepth = v.depth if v.kind != "param" else 0
            if not path:
                outer = lambda x: self.fn.vars[x].depth <= v.depth and self.fn.vars[x].blk != vid
                repoint = cur is not None and cur.own == "L"
                new = self.rvalue(st, rv, ln, ddepth, v.ty, v.name, copy_ok=v.kind == "temp", dest_vid=vid,
                                  lend_owner=outer if v.kind == "temp" else ((lambda x: True) if v.mut and repoint else (lambda x: False)))
                own_parts = cur is not None and cur.own == "O" and new.own == "L" and any(
                    self.loans.get(l, ((None,),))[0][0] == vid for l in new.loans) and v.kind != "temp"
                if own_parts:
                    # `= o ( f o … )`: o is given (a part of) its own value back
                    # - it keeps owning it; nothing is released (the keep rule)
                    rest = {l for l in new.loans if self.loans.get(l, ((None,),))[0][0] != vid}
                    st.vals[vid] = AV("O", rest, frozenset(), cur.held | new.held)
                    return st
                if cur is not None and cur.own in ("O", "P"):
                    self.handover(st, (vid, ()))
                    self.effect(st, (vid, ()), "replace", ln)
                if cur is not None and cur.own == "P":
                    held = (new.held | hfrom(new.loans)) if new.own == "L" else new.held
                    st.vals[vid] = AV("P", (), (), held)
                else:
                    st.vals[vid] = new
                return st
            fty = self.ty_of_place((vid, path))
            new = self.rvalue(st, rv, ln, ddepth, fty, self.pname((vid, path)))
            if cur is not None and cur.own in ("M", "X", "D"):
                self.err(ln, f"{v.name} is used after it was moved")
            add = (hfrom(new.loans) | new.held) if new.own == "L" else new.held
            vty = v.ty
            if cur is not None and cur.own == "L" and vty is not None and vty[0] == "named" and path[0] != "*":
                # a struct cursor is a copy of the struct: its field store
                # writes the copy; the value it replaced stays the owner's
                st.vals[vid] = AV("L", cur.loans, cur.alias, cur.held | hroot(add, path))
                return st
            self.handover(st, (vid, path))
            self.effect(st, (vid, path), "replace", ln)
            self.store_into(st, (vid, path), add)
            return st
        if k == "eval":
            _, rv, ln = s
            self.rvalue(st, rv, ln, 99, None, "value")
            return st
        if k == "drop":
            _, vid, ln = s
            av = st.vals.get(vid)
            if av and av.own == "O":
                self.effect(st, (vid, ()), "replace", ln)
                st.vals[vid] = AV("D")
            return st
        if k == "scope":
            _, body, ln = s
            st = self.run(st, body)
            return self.scope_end(st, body, ln)
        if k == "if":
            _, op, a, b, ln = s
            self.read(st, op, ln, ("if", id(s)))
            return join(self.run(st.copy(), a), self.run(st.copy(), b))
        if k == "match":
            _, op, arms, ln = s
            self.read(st, op, ln, ("m", id(s)))
            out = State(bottom=True)
            for vname, body in arms:
                out = join(out, self.run(st.copy(), body))
            return out
        if k == "while":
            _, cond, cop, body, ln = s
            return self.loop(st, s, cond, cop, body, ln)
        if k == "foreach":
            _, vid, sop, body, ln = s
            return self.foreach(st, s, vid, sop, body, ln)
        if k == "ret":
            _, op, ln = s
            if op is not None:
                av = self.transfer(st, op, ln, ("ret", id(s)), 0, self.fn.ret, "the returned value",
                                   copy_ok=True, is_ret=True)
                self.check_live(st, av, ln, "the returned value", held=True)
                self.rets.append((av, st.copy()))
            else:
                self.exits.append(st.copy())
            return State(bottom=True)
        if k == "break":
            if self.loop_stack:
                self.loop_stack[-1][0].append(st.copy())
            return State(bottom=True)
        if k == "continue":
            if self.loop_stack:
                self.loop_stack[-1][1].append(st.copy())
            return State(bottom=True)
        raise CheckError(f"stmt {k}")

    def loop(self, st, s, cond, cop, body, ln):
        head = st.copy()
        final = self.final
        self.final = False
        for _ in range(12):
            self.loop_stack.append(([], []))
            c = self.run(head.copy(), cond)
            if not c.bottom:
                self.read(c, cop, ln, ("wc", id(s)))
            b = self.run(c.copy(), body)
            _, conts = self.loop_stack.pop()
            nxt = join(head, b)
            for x in conts:
                nxt = join(nxt, x)
            if nxt.key() == head.key():
                break
            head = nxt
        self.final = final
        self.loop_stack.append(([], []))
        c = self.run(head.copy(), cond)
        if not c.bottom:
            self.read(c, cop, ln, ("wc", id(s)))
        self.run(c.copy(), body)
        breaks, _ = self.loop_stack.pop()
        out = c
        for x in breaks:
            out = join(out, x)
        return out

    def foreach(self, st, s, vid, sop, body, ln):
        src = self.read(st, sop, ln, ("fs", id(s)), "the loop's container")
        self.check_live(st, src, ln, "the loop's container", held=True)
        # the loop walks the container's buffer for as long as it runs
        walk = set(src.loans)
        elem_alias = set()
        for a in src.alias:
            walk.add(self.loan(st, ("fw", id(s), a), a, "view"))
            elem_alias.add((a[0], a[1] + ("*",)))
        head = st.copy()
        final = self.final
        self.final = False
        for _ in range(12):
            nxt, _ = self._fe_round(head, s, vid, walk, elem_alias, src, body, ln)
            if nxt.key() == head.key():
                break
            head = nxt
        self.final = final
        _, out = self._fe_round(head, s, vid, walk, elem_alias, src, body, ln)
        return out

    def _fe_round(self, head, s, vid, walk, elem_alias, src, body, ln):
        self.loop_stack.append(([], []))
        cur = head.copy()
        if walk & cur.dead:
            self.err(ln, "the loop's container was changed while the loop walks it")
        loans = set(src.loans)
        for a in elem_alias:
            loans.add(self.loan(cur, ("fe", id(s), a), a, "handle"))
        ety = self.fn.vars[vid].ty
        if ety is not None and self.T.is_scalar(ety):
            cur.vals[vid] = NONE
        elif ety is not None and ety[0] in VIEW_TYPES:
            v = self.view_value(hsub(src.held, ("*",)))
            cur.vals[vid] = AV("L", v.loans | src.loans, v.alias, frozenset()) if v.own == "L" else NONE
        else:
            cur.vals[vid] = AV("L", loans, elem_alias, hsub(src.held, ("*",)))
        b = self.run(cur, body)
        breaks, conts = self.loop_stack.pop()
        nxt = join(head, b)
        for x in conts:
            nxt = join(nxt, x)
        out = nxt
        for x in breaks:
            out = join(out, x)
        return nxt, out

    # -- the whole function ----------------------------------------------------
    def check(self):
        st = State()
        for vid in self.fn.params:
            v = self.fn.vars[vid]
            st.vals[vid] = NONE if v.ty is not None and self.T.is_scalar(v.ty) else AV("P")
        end = self.run(st, self.fn.body)
        if not end.bottom:
            self.exits.append(end)
        return self.make_summary()

    def param_loan(self, lid):
        if lid not in self.loans:
            return None
        place, kind = self.loans[lid]
        if place[0] in self.pidx:
            return self.pidx[place[0]], place[1][:3], kind
        return None

    def make_summary(self):
        res = "none"
        lends, rholds = set(), set()
        for av, _ in self.rets:
            if av.own in ("O", "P"):
                res = "own" if res in ("none", "own") else res
            elif av.own == "L":
                res = "lent"
            for lid in av.loans:
                pl = self.param_loan(lid)
                if pl:
                    lends.add(pl)
            for hp, lid in av.held:
                pl = self.param_loan(lid)
                if pl:
                    rholds.add((hp[:3],) + pl)
        if self.fn.ret is not None and self.T.is_scalar(self.fn.ret):
            res = "none"
        if res == "lent" and not lends:
            res = "own"
        stores = set()
        for st in [s for _, s in self.rets] + self.exits:
            for vid, j in self.pidx.items():
                av = st.vals.get(vid)
                if av is None:
                    continue
                for hp, lid in av.held:
                    pl = self.param_loan(lid)
                    if pl:
                        stores.add((j, hp[:3]) + pl)
        consumes = set(self.s_consumes) | {k for k, m in enumerate(self.fn.modes) if m == "sink"}
        return {"modes": list(self.fn.modes), "res": res, "lends": sorted(lends), "rholds": sorted(rholds),
                "effects": sorted(self.s_effects), "stores": sorted(stores),
                "consumes": sorted(consumes), "elems": sorted(self.s_elems)}


def initial_summary(prog, fn):
    T = Types(prog)
    return {"modes": list(fn.modes), "res": "none" if fn.ret is None or T.is_scalar(fn.ret) else "own",
            "lends": [], "rholds": [], "effects": [], "stores": [],
            "consumes": [k for k, m in enumerate(fn.modes) if m == "sink"], "elems": []}


def check_program(prog, max_rounds=40):
    summ = {name: initial_summary(prog, fn) for name, fn in prog.fns.items()}
    for _ in range(max_rounds):
        changed = False
        for name, fn in prog.fns.items():
            new = FnCheck(prog, fn, summ, final=False).check()
            merged = merge_summary(summ[name], new)
            if merged != summ[name]:
                summ[name] = merged
                changed = True
        if not changed:
            break
    errors = []
    for name, fn in prog.fns.items():
        fc = FnCheck(prog, fn, summ, final=True)
        fc.check()
        errors += fc.errors
    return errors, summ


def tuple_ify(x):
    if isinstance(x, (list, tuple)):
        return tuple(tuple_ify(i) for i in x)
    return x


def merge_summary(a, b):
    """Summaries only grow, so the fixpoint terminates."""
    order = {"none": 0, "own": 1, "lent": 2}
    out = {"modes": a["modes"], "res": a["res"] if order[a["res"]] >= order[b["res"]] else b["res"]}
    for key in ("lends", "rholds", "effects", "stores", "consumes", "elems"):
        out[key] = sorted(set(map(tuple_ify, a[key])) | set(map(tuple_ify, b[key])), key=repr)
    return out
