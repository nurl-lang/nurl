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
import os
import sys

from prims import PRIMS
from lower import Types, Var

# NCORE_DERIVE=1: a library function's derived summary (derive.py) answers
# before its declared one - how far the walk's own answers carry.
DERIVE_FIRST = os.environ.get("NCORE_DERIVE") == "1"
PATH_MAX = 5

# NCORE_TRACE=<binding>: say on stderr where an effect on it ends a loan.
TRACE = os.environ.get("NCORE_TRACE")


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
    __slots__ = ("own", "loans", "alias", "held", "call")

    def __init__(self, own, loans=frozenset(), alias=frozenset(), held=frozenset(), call=False):
        self.own, self.loans, self.alias, self.held = own, frozenset(loans), frozenset(alias), frozenset(held)
        # a lend a call handed back: a copy of the handle in its owner, not
        # the owner's part read in place
        self.call = call

    def key(self):
        return (self.own, self.loans, self.alias, self.held, self.call)

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
    __slots__ = ("vals", "dead", "bottom", "defers", "gone")

    def __init__(self, vals=None, dead=frozenset(), bottom=False, defers=(), gone=frozenset()):
        self.vals = dict(vals or {})
        self.dead = frozenset(dead)
        self.bottom = bottom
        self.defers = tuple(defers)      # the `;` blocks armed so far, oldest first
        self.gone = frozenset(gone)      # (variable, path): a field taken out of its owner

    def copy(self):
        return State(self.vals, self.dead, self.bottom, self.defers, self.gone)

    def key(self):
        return (self.bottom, self.dead, self.defers, self.gone,
                tuple(sorted(((k, v.key()) for k, v in self.vals.items()), key=repr)))


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
        vals[k] = AV(join_own(x.own, y.own), x.loans | y.loans, x.alias | y.alias, x.held | y.held,
                     x.call or y.call)
    # a block armed on one path may run: it is checked as if it does
    defers = a.defers + tuple(d for d in b.defers if d not in a.defers)
    return State(vals, a.dead | b.dead, defers=defers, gone=a.gone | b.gone)


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
        # What a parameter's value holds is the caller's to say. One loan
        # stands for it (kind `held`), on a place of its own that nothing in
        # this frame changes; the summary hands it on by the parameter's
        # number, and each call puts what its argument holds in its place.
        self.hvid = {}
        for i, vid in enumerate(fn.params):
            h = -1 - vid
            if h not in fn.vars:
                fn.vars[h] = Var(h, f"what {fn.vars[vid].name} holds", None, "param", fn.vars[vid].line, 0)
            self.hvid[h] = i
        self.s_effects = set()
        self.s_consumes = set()
        self.s_elems = set()
        self.rets = []
        self.exits = []
        self.loop_stack = []
        self.defer_bodies = []
        self.tails_memo = {}
        self.agg_lends = {}      # a literal temporary -> the bindings it shows and has not taken
        self.temp_fresh = {}
        self.call_lent = {}      # a call's temporary -> the arguments it may hand back whole
        self.cap_loans = set()   # the loans that are a closure's own handle of a binding it captured
        self.lit_nocopy = {}     # a literal temporary -> its field that borrows a value with no copy
        self.lit_lendcopy = set()  # literal temporaries around a part of a parameter that can be copied
        self.call_by_fn = {}     # a call's temporary -> the callee is a function of the program
        self.slot_vars = set()   # payload bindings of a library getter's option: a container's slot
        self.call_mixed = set()  # the temporaries of calls whose result is the caller's own on some calls
        self.ret_fresh = False   # some return hands back a value of the function's own that holds something
        self.temp_none = {}      # a literal temporary -> it is an option's `None`
        self.var_fresh = set()   # the variables given a value of their own that is no `None`
        self.ret_watch = None    # the binding a return handed back, while its `;` blocks run
        self.defer_vars = {}     # a `;` block -> the variables its body names
        self.ret_changed = False
        self.walking = set()
        self.moved_from = None   # the last value moved that holds views of its own parts     # the loans of the loops being walked: their containers' buffers     # a temporary -> its value is what a call made and handed over
        self.s_invokes = set()
        self.s_detaches = set()
        self.s_cloargs = set()
        self.s_retparams = set()
        self.s_regions = set()
        self.s_selfholds = set()
        self.ncap = getattr(fn, "ncap", 0)

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
        return self.ty_at(self.fn.vars[vid].ty, path)

    def ty_at(self, ty, path):
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
        # (a place is followed PATH_MAX steps deep: a walk down a recursive
        # value - a cursor repointed at its own payload's payload - names
        # the place that deep and stops)
        if len(place[1]) > PATH_MAX:
            place = (place[0], place[1][:PATH_MAX])
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
        if q[0] == p[0] and self.kills_paths(eff, p, p[1], q, q[1], k):
            return True
        if eff == "take" and lid in self.cap_loans and q[0] == p[0] and prefix(q[1], p[1]) and k != "ref":
            # (a closure that captured the value around the part taken may
            # read that part when it runs)
            return True
        # A shared payload - what every copy of an Rc / Arc / Shared handle
        # reaches - is one place per handle type: which handles are copies
        # of one another is not known here (PROPOSAL_CORE_IR D3), so an
        # effect inside a payload of that type ends what was lent out of
        # any payload of it.
        ps = self.shared_tails(p)
        if not ps:
            return False
        for (ty, qtail) in self.shared_tails(q):
            for (pty, ptail) in ps:
                if ty == pty and self.kills_paths(eff, p, ptail, q, qtail, k):
                    return True
        return False

    def region_effect(self, st, ty, tail, eff):
        """An effect at `tail` inside some payload of shared handle type
        `ty`: ends what was lent out of any payload of that type."""
        self.s_regions.add((ty, tail[:3], eff))
        killed = set()
        for lid in self.loans:
            if lid in st.dead:
                continue
            (q, k) = self.loans[lid]
            for (qty, qtail) in self.shared_tails(q):
                if qty == ty and self.kills_paths(eff, None, tail, q, qtail, k):
                    killed.add(lid)
                    break
        if killed:
            st.dead = st.dead | killed

    def shared_tails(self, place):
        """(handle type, path below its payload) for every shared handle the
        place reaches through."""
        memo = self.tails_memo
        if place in memo:
            return memo[place]
        out = []
        shared = getattr(self.prog, "shared", None)
        if shared:
            vid, path = place
            ty = self.fn.vars[vid].ty
            for i, e in enumerate(path):
                if ty is None:
                    break
                if e == "*" and ty[0] == "named" and ty[1] in shared:
                    out.append((ty[1], path[i + 1:]))
                ty = self.ty_of_place((vid, path[:i + 1]))
        memo[place] = out
        return out

    def kills_paths(self, eff, p, pp, q, qp, k):
        if k in ("share", "held"):
            return False
        if eff == "take":
            # a part moved out of where it lived: what was lent out of that
            # part ends, a handle of the value around it does not
            return k != "ref" and prefix(pp, qp)
        if k == "ref" or eff == "end":
            # a pointer to the binding itself: good while the binding is,
            # whatever value it is given - and only that ends with it
            return k == "ref" and eff == "end" and prefix(pp, qp)
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
        if vid == self.ret_watch and eff != "end":
            self.ret_changed = True
        if av.own == "L" and eff != "end":
            for a in av.alias:
                self.effect(st, (a[0], a[1] + path), eff, line, depth + 1)
            return
        shown = self.agg_lends.get(vid)
        if shown and path and path[0] in shown and eff != "end":
            # a field of a literal temporary that shows a binding: what is
            # done to it is done to the binding
            self.effect(st, (shown[path[0]], path[1:]), eff, line, depth + 1)
        if vid in self.pidx and eff != "end":
            self.s_effects.add((self.pidx[vid], path[:3], eff))
        if eff != "end":
            # an effect inside a shared payload is one on that handle type's
            # payload, whichever handle it was reached through: the callers'
            # too (the summary's `regions`)
            arcs = getattr(self.prog, "arcs", ())
            for (ty, tail) in self.shared_tails(place):
                self.s_regions.add((ty, tail[:3], eff))
                if ty in arcs:
                    # every thread holding a copy of the Arc reads its
                    # payload: nothing changes it in place (MEMORY.md §6.5)
                    self.err(line, f"{self.pname(place)} is inside what an Arc shares, and is changed here")
        killed = {l for l in self.loans if l not in st.dead and self.kills(eff, place, l)}
        if killed:
            if TRACE and self.final and self.vname(vid) == TRACE:
                print(f"trace: {self.fn.name}:{line}: {eff} on {self.pname(place)} ends {len(killed)} loan(s)", file=sys.stderr)
            st.dead = st.dead | killed
        # what the place held is gone with what the effect released
        if eff in ("drop", "replace", "take") and av.held:
            keep = set()
            for hp, l in av.held:
                if eff in ("replace", "take") and prefix(path, hp):
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
        alias = {self.loans[l][0] for l in loans if l in self.loans and self.loans[l][1] != "held"}
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
        if av.held and not path:
            # a value that holds a view - one stored into it, or captured by
            # it - is read whole: what the view points into must still be
            # there (MEMORY.md §2.10)
            self.check_live(st, av, line, name, held=True)
        if st.gone:
            for (gv, gp) in st.gone:
                if gv == vid and (prefix(gp, path) or prefix(path, gp)):
                    self.err(line, f"{self.pname((vid, gp))} is used after it was taken out of {name}")
                    return NONE
        ty = self.ty_of_place((vid, path))
        if ty is not None and self.T.is_scalar(ty):
            if path:
                self.check_live(st, AV("N", held=hsub(av.held, path)), line, name, held=True)
            return NONE
        sub = hsub(av.held, path) if path else av.held
        if av.own in ("O", "P"):
            if not path:
                if (av.own == "P" and ty is not None and ty[0] in VIEW_TYPES
                        and self.fn.modes[self.pidx[vid]] != "sink"):
                    # a raw string or slice parameter is a view the caller
                    # lent: read, it is that view, never an owner to move
                    return AV("L", {self.loan(st, site, (vid, ()), "view")}, {(vid, ())}, av.held)
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

    def fresh_string_kept(self, st, op, cur, line, where):
        """A fresh raw string - the result of a call that hands its string
        over - kept by a value (a field, an element) is owned by nothing: a
        raw string in a value is a view (MEMORY.md §2.13)."""
        v = self.fn.vars[op[1]]
        if (v.kind == "temp" and v.ty is not None and v.ty[0] == "s" and cur.own == "O" and not op[2]
                and not cur.held and self.temp_fresh.get(op[1])):
            self.err(line, f"a fresh string handed to {where} is owned by nothing")

    def reroot(self, st, av, dest, base=()):
        """The value just moved into `dest` (at path `base`) holds views of
        its own parts: they are views of `dest`'s parts now."""
        mf, self.moved_from = self.moved_from, None
        if not mf:
            return av
        src, own = mf
        held = set()
        for hp, l in av.held:
            if l in own:
                place, kind = self.loans[l]
                nl = ("rr", l, dest, base)
                self.loans[nl] = ((dest, base + place[1]), kind)
                held.add((hp, nl))
            else:
                held.add((hp, l))
        return AV(av.own, av.loans, av.alias, held, av.call)

    def lent_part(self, av):
        """A part read out of a value that holds it as a lend - a field the
        value was given a handle copy for - is that lend, not an owner."""
        # (what a parameter holds, `held`, is held somewhere inside: it does
        # not make the part a lend)
        own = {l for hp, l in av.held if not hp and l in self.loans and self.loans[l][1] != "held"}
        if not own:
            return av
        alias = {self.loans[l][0] for l in own}
        return AV("L", av.loans | own, av.alias | alias, {(hp, l) for hp, l in av.held if hp or l not in own}, True)

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
        named = self.agg_lends.pop(vid, None)
        if named:
            # the literal is taken: the bindings it showed move into it
            gone = set()
            for b in named.values():
                cur = st.vals.get(b)
                if cur is not None and cur.own == "O":
                    gone |= {l for hp, l in src.held if l in self.loans and self.loans[l] == ((b, ()), "handle")}
                    self.effect(st, (b, ()), "replace", line)
                    st.vals[b] = AV("M")
            src = AV(src.own, src.loans, src.alias, {(hp, l) for hp, l in src.held if l not in gone}, src.call)
            st.vals[vid] = src
        if src.own == "P":
            self.s_consumes.add(self.pidx[vid])
        # (what the value holds of its own parts - an index field viewing
        # its arena field - goes with it: those loans are re-rooted at its
        # new holder, reroot)
        own = {l for hp, l in src.held if l in self.loans and self.loans[l][0][0] == vid}
        self.effect(st, (vid, ()), "replace", line)
        st.dead = st.dead - own
        st.vals[vid] = AV("M")
        self.moved_from = (vid, own) if own else None
        return AV("O", src.loans, frozenset(), src.held)

    def refers_to_block(self, av, blk):
        for lid in av.loans:
            if lid in self.loans and self.fn.vars[self.loans[lid][0][0]].blk == blk:
                return True
        return any(self.fn.vars[a[0]].blk == blk for a in av.alias)

    def transfer(self, st, op, line, site, dest_depth, dest_ty, what, copy_ok=False, is_ret=False,
                 lend_owner=lambda vid: False, dest_vid=None, named=False, stored=False):
        """A value handed to a new holder (a let, `=`, a return, a field): an
        owner moves; a lend is copied with its loans, or - where it would
        outlive a local it borrows from - deep-copied (a join's value, a
        return) or refused."""
        av = self.read(st, op, line, site, what)
        if op[0] == "v" and not op[2] and op[1] in self.lit_lendcopy and not is_ret and av.own == "L":
            # (taken by something other than a return: the copy is made)
            av = AV("O", (), (), av.held)
            st.vals[op[1]] = av
        if op[0] == "v" and not op[2] and op[1] in self.lit_nocopy and not is_ret:
            self.err(line, f"field {self.lit_nocopy[op[1]]}: a borrowed value would have to be copied here, "
                           f"and it cannot be copied")
        if op[0] == "v" and op[2] and av.own == "L" and "*" not in op[2]:
            root = st.vals.get(op[1])
            pty = self.ty_of_place((op[1], op[2]))
            if (root is not None and root.own == "O" and self.fn.vars[op[1]].kind == "temp"
                    and pty is not None and pty[0] not in VIEW_TYPES
                    and (self.T.owning(pty) or pty[0] == "closure")):
                # a field read off a temporary leaves it: whatever takes the
                # read owns it, and the temporary's rest is released where
                # its statement ends (MEMORY.md §7.5 table, h323)
                mine = {l for l in av.loans if self.loans.get(l, (None,))[0] == (op[1], op[2])}
                av = AV("O", av.loans - mine, (), av.held)
        if op[0] == "v" and not op[2] and av.own in ("O", "P"):
            vid = op[1]
            src = st.vals[vid]
            vty = self.fn.vars[vid].ty
            raw = vty is not None and vty[0] in VIEW_TYPES
            to_view = dest_ty is not None and dest_ty[0] == "s" and vty is not None and vty[0] != "s"
            dv = self.fn.vars[dest_vid] if dest_vid is not None else None
            if to_view:
                av = AV("L", {self.loan(st, site, (vid, ()), "view")}, {(vid, ())}, frozenset())
            elif (src.own == "O" and vty is not None and vty[0] == "s" and self.fn.vars[vid].kind != "temp"
                  and dv is not None and dv.mut and dv.kind == "local" and not is_ret):
                # `: ~ s y x`, x an owned raw string: a slot of its own is
                # given a copy of the text (MEMORY.md §7.6, owned string slots)
                av = AV("O", (), (), frozenset())
            elif (stored and vty is not None and vty[0] == "closure" and self.fn.vars[vid].kind != "temp"
                  and not is_ret):
                # a closure binding (or parameter) stored into a literal:
                # the literal owns a copy of it (MEMORY.md §7.5, agora #173)
                av = AV("O", (), (), self.closure_owned(src.held))
            elif src.own == "P" or (self.fn.vars[vid].kind != "temp" and (
                    (raw and not is_ret and not (stored and vty[0] == "slice")) or lend_owner(vid))):
                # a parameter is lent to its new name (the caller owns it); an
                # owned raw string or slice is viewed, not moved
                av = AV("L", {self.loan(st, site, (vid, ()), "view" if raw else "handle")}, {(vid, ())}, src.held)
            else:
                av = self.move_out(st, vid, line)
                if is_ret and self.moved_from:
                    # (its views of its own parts leave with it: they are no
                    # views of this frame's values)
                    own = self.moved_from[1]
                    for hp, l in av.held:
                        if l in own:
                            # (…and the caller's result holds them: `selfholds`)
                            self.s_selfholds.add((hp[:3], self.loans[l][0][1][:3], self.loans[l][1]))
                    av = AV(av.own, av.loans, av.alias, {(hp, l) for hp, l in av.held if l not in own}, av.call)
                    self.moved_from = None
        if av.held and is_ret:
            av = self.closure_takes_over(st, av, line, op[0] == "v" and self.fn.vars[op[1]].kind == "temp")
        if (av.held and is_ret and op[0] == "v" and self.fn.vars[op[1]].kind == "temp"
                and self.local_depth(AV("N", held=av.held)) > dest_depth):
            # a closure literal handed back as it is takes over what it
            # captured (§7.5); a binding of one - handed back by name, or
            # assigned to a binding that outlives its captures - holds only
            # copies of their handles (MEMORY.md §2.11, h310)
            av = AV(av.own, av.loans, av.alias, self.closure_owned(av.held), av.call)
        own_block = dest_vid is not None and self.refers_to_block(av, dest_vid)
        if is_ret and av.own == "L" and not av.call and av.alias and op[0] == "v" and not op[2]:
            # what a `?` / `??` or a value block selected among this
            # frame's owners goes to the caller with the return: the one
            # selected moves out (MEMORY.md §2.2); a parameter it may be
            # instead is lent, as before
            # (a view handed back - `s`, a slice - selects an owner only
            # where the owner is itself one: an owned raw string, an owned
            # slice. A view of a String's buffer owns nothing.)
            viewish = dest_ty is not None and dest_ty[0] in VIEW_TYPES
            mine = [a for a in av.alias if (st.vals.get(a[0]) is not None and st.vals[a[0]].own == "O"
                                            and self.fn.vars[a[0]].kind != "param" and "*" not in a[1]
                                            and (not viewish or (self.ty_of_place(a) or ("?",))[0] == dest_ty[0]))]
            if mine and self.fn.vars[op[1]].kind == "temp":
                gone = set()
                for a in mine:
                    gone |= {l for l in av.loans if self.loans.get(l, (None,))[0][0:1] == (a[0],)}
                    self.effect(st, a, "replace", line)
                    if not a[1]:
                        st.vals[a[0]] = AV("M" if len(av.alias) == 1 else "X")
                rest = av.loans - gone
                av = AV("L" if rest else "O", rest, av.alias - set(mine), av.held, av.call)
        # (a value that is its own on some paths and a lend on others - a
        # join of a fresh value and a borrowed one - is copied on the paths
        # that lend it, where its new holder outlives what it borrows)
        mixed = av.own == "O" and av.loans
        if (av.own == "L" or mixed) and (own_block or self.local_depth(AV("L", av.loans, av.alias)) > dest_depth):
            if copy_ok and dest_ty is not None and self.T.copyable(dest_ty) and not self.T.is_scalar(dest_ty):
                av = AV("O", (), (), av.held)
            elif own_block:
                return av
            elif copy_ok and not is_ret and not named:
                # a join's or block's value that cannot be copied stays a
                # lend: if what it borrows ends first, its use is the error
                return av
            elif mixed:
                pass
            else:
                self.err(line, f"{what}: a view of a value released before its holder escapes")
        if av.held and self.local_depth(AV("N", held=av.held)) > dest_depth and copy_ok and dest_ty is not None:
            # a part the value holds as a lend of something that ends before
            # its new holder - a payload a callee lent, a field read into a
            # literal - is copied where it can be (MEMORY.md §7.6, "borrowed
            # values are copied into owners")
            keep = set()
            for hp, l in av.held:
                if l in self.loans and self.loans[l][1] == "handle":
                    v = self.fn.vars[self.loans[l][0][0]]
                    pty = self.ty_at(dest_ty, hp)
                    if (v.kind != "param" and v.depth > dest_depth and pty is not None
                            and pty[0] not in VIEW_TYPES and self.T.copyable(pty)):
                        continue
                keep.add((hp, l))
            av = AV(av.own, av.loans, av.alias, keep, av.call)
        if av.held and self.local_depth(AV("N", held=av.held)) > dest_depth and not (copy_ok and not is_ret and not named):
            self.err(line, f"{what}: holds a view of a value released before it")
        return av

    # -- calls -----------------------------------------------------------------
    def summary(self, name):
        if name in self.summ:
            return self.summ[name]
        derived = getattr(self.prog, "derived", None)
        if derived is not None and DERIVE_FIRST and derived(name) is not None:
            return derived(name)
        if PRIMS.get(name) is not None:
            return PRIMS[name]
        # a `dyn` method's virtual callee may run any impl of the method
        impls = getattr(self.prog, "virt", {}).get(name)
        if impls:
            out = None
            for m in impls:
                sm = self.summ.get(m)
                if sm is None:
                    continue
                out = sm if out is None else merge_summary(out, sm)
            if out is not None:
                return out
        # a generic's instance answers as its template does
        tmpl = getattr(self.prog, "fn_tmpl", {}).get(name)
        if tmpl and PRIMS.get(tmpl) is not None:
            return PRIMS[tmpl]
        # a library function with no declared summary: what the walk
        # believes of it (derive.py)
        if derived is not None and derived(name) is not None:
            return derived(name)
        from syntax import Unsupported
        raise Unsupported(f"no summary for {tmpl or name}")

    def apply_call(self, st, rv, line, dest_vid=None):
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
        # (an argument the call stores by value where it replaces is read -
        # copied, or taken out of the old value - before the old value goes:
        # a lend of the element given back to the same element)
        stored_back = {(j, src) for (j, dp, src, pth, kind) in sm["stores"] if kind == "value"}
        for (k, path, eff) in sm["effects"]:
            if k >= len(ops) or ops[k][0] != "v":
                continue
            place = (ops[k][1], ops[k][2] + tuple(path))
            for m, av in enumerate(avs):
                if eff == "replace" and (k, m) in stored_back:
                    continue
                if m != k and self.would_kill(st, place, eff, av.loans | hloans(av.held)):
                    self.err(line, f"{name}: argument {m + 1} views what the call changes through argument {k + 1}")
                elif m == k and self.would_kill(st, place, eff, hloans(av.held)):
                    # A2: an argument is frozen for the call - a part of it may
                    # not view what the call changes in another part
                    self.err(line, f"{name}: a part of argument {k + 1} views what the call changes in it")
        # a closure that changes what it captured is a second route to it: it
        # may not meet another argument that reaches that capture (§2.4, §2.11)
        for k, av in enumerate(avs):
            for place, eff in self.closure_capture_effects(av):
                for m, other in enumerate(avs):
                    if m == k:
                        continue
                    reach = any(a[0] == place[0] and (prefix(a[1], place[1]) or prefix(place[1], a[1]))
                                for a in other.alias)
                    reach = reach or (ops[m][0] == "v" and ops[m][1] == place[0]
                                      and (prefix(ops[m][2], place[1]) or prefix(place[1], ops[m][2])))
                    if reach or self.would_kill(st, place, eff, other.loans | hloans(other.held)):
                        self.err(line, f"{name}: the closure in argument {k + 1} changes "
                                       f"{self.pname(place)}, which argument {m + 1} also reaches")
        # a closure several threads may run at once changes nothing it
        # captured (MEMORY.md §6.5)
        for k in sm.get("shares", ()):
            if k < len(avs) and self.closure_capture_effects(avs[k]):
                self.err(line, f"{name}: the closure in argument {k + 1} changes what it captured, "
                               f"and several threads may run it at once")
        # an `inout` argument is the callee's alone for the call: no other
        # argument is the same binding, a part of it, or a lend of it
        # (MEMORY.md §2.4)
        for k, mode in enumerate(sm["modes"][:len(ops)]):
            if mode != "inout" or ops[k][0] != "v":
                continue
            _, vid, path = ops[k]
            for m, op in enumerate(ops):
                if m == k:
                    continue
                same = op[0] == "v" and op[1] == vid and (prefix(op[2], path) or prefix(path, op[2]))
                lend = any(a[0] == vid and (prefix(a[1], path) or prefix(path, a[1])) for a in avs[m].alias)
                if same or lend:
                    self.err(line, f"{name}: argument {k + 1} is handed over to be changed (`inout`), "
                                   f"and argument {m + 1} reaches it too")
                    break
        # consumed arguments
        copied = set()
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
                cv = self.fn.vars[op[1]]
                if cur and cur.own in ("O", "P") and cv.kind != "temp" and cv.ty is not None and cv.ty[0] == "closure":
                    # a closure binding handed to a keeper: the keeper has a
                    # copy, the binding keeps its own (MEMORY.md §7.5)
                    copied.add(k)
                    continue
                if cur and cur.own == "O" and cv.kind != "temp" and cv.ty is not None and cv.ty[0] == "s":
                    # an owned raw string in a binding: a keeper copies it,
                    # the binding keeps its buffer (MEMORY.md §7.6)
                    copied.add(k)
                    continue
                if cur and cur.own in ("O", "P"):
                    moved = self.move_out(st, op[1], line)
                    # (what the callee keeps of it is what the value holds
                    # now that it is taken)
                    avs[k] = AV(avs[k].own, avs[k].loans, avs[k].alias, moved.held, avs[k].call)
                    continue
            if avs[k].own == "L" and op[0] == "v" and not op[2] and op[1] in self.lit_lendcopy:
                # (a literal around a part of a parameter, handed to a
                # consumer: the copy is made for it)
                copied.add(k)
                continue
            if avs[k].own == "L":
                ty = self.ty_of_place((op[1], op[2])) if op[0] == "v" else None
                if ty is not None and self.T.owns_handle(ty):
                    # a part read in place out of its owner is taken out of
                    # it; any other borrowed value is handed over as a copy
                    # (MEMORY.md §7.6: an owner moves, a borrow is copied)
                    if avs[k].call:
                        # what a call lent is a copy of a handle its owner
                        # keeps: a temporary is handed over as a copy of the
                        # value, a binding of it is not the binding's to give
                        if self.fn.vars[op[1]].kind != "temp" or op[2]:
                            self.err(line, f"{name} takes {self.pname((op[1], op[2]))}, which is a borrow")
                        elif not self.T.copyable(ty):
                            self.err(line, f"{name} takes a borrowed value that cannot be copied")
                    elif (not op[2] and self.fn.vars[op[1]].kind == "local" and avs[k].alias
                          and k < len(sm["modes"]) and sm["modes"][k] == "sink"
                          # (a value with a destructor of its own under
                          # another name is that value: agora #768)
                          and not (ty[0] == "named" and ("drop__" + ty[1]) in getattr(self.prog, "fn_flags", ())
                                   and not self.fn.vars[op[1]].mut)
                          and all(not a[1] and st.vals.get(a[0]) is not None
                                  and ((a[0] in self.pidx and st.vals[a[0]].own == "P"
                                        and self.fn.modes[self.pidx[a[0]]] == "in")
                                       or (st.vals[a[0]].own == "O" and self.fn.vars[op[1]].mut))
                                  for a in avs[k].alias)):
                        # a second name of a parameter the caller keeps, or
                        # a `: ~` cursor of a binding: a borrow, not this
                        # name's to hand to a `sink` (a callee that merely
                        # keeps it takes the owner over through it instead)
                        self.err(line, f"{name} takes {self.vname(op[1])}, which is a borrow of another binding's value")
                    elif not self.take_payload(st, avs[k], line, direct=bool(op[2])) and not self.T.copyable(ty):
                        self.err(line, f"{name} takes a borrowed value that cannot be copied")
                elif ty is not None and ty[0] == "closure":
                    # a borrowed closure handed to a keeper is copied: what
                    # the callee does to its own copy is not done to the
                    # caller's (MEMORY.md §7.5)
                    copied.add(k)
        # effects
        for (k, path, eff) in sm["effects"]:
            if k < len(ops) and ops[k][0] == "v" and not (k in copied and not path):
                self.effect(st, (ops[k][1], ops[k][2] + tuple(path)), eff, line)
        for (k, path) in sm.get("gone", ()):
            if k < len(ops) and ops[k][0] == "v":
                st.gone = st.gone | {(ops[k][1], ops[k][2] + tuple(path))}
        # what the callee may do inside a shared payload, whichever handle it
        # reaches it through
        for (ty, tail, eff) in sm.get("regions", ()):
            self.region_effect(st, ty, tuple(tail), eff)
        # a closure another thread runs takes what it captured with it
        for k in sm.get("detaches", ()):
            if k < len(avs):
                if ops[k][0] == "v" and not ops[k][2] and ops[k][1] in self.pidx:
                    # (a parameter handed on to a callee that detaches it:
                    # this function detaches its argument)
                    self.s_detaches.add(self.pidx[ops[k][1]])
                for hp, l in avs[k].held:
                    if l in self.loans and self.loans[l][1] == "view" and any(x.startswith("^") for x in hp):
                        # what another thread runs holds no view: this side
                        # may release what it points into while the other
                        # runs (MEMORY.md §6.5)
                        self.err(line, f"{name}: what another thread runs holds a view of "
                                       f"{self.pname(self.loans[l][0])}")
                        break
                for hp, l in avs[k].held:
                    if l in self.loans and hp and hp[-1].startswith("^") and hp[-1] != "^f":
                        place = self.loans[l][0]
                        if self.loans[l][1] == "ref":
                            self.err(line, f"{name}: the closure points into this frame through "
                                           f"{self.pname(place)}, and another thread would run it")
                            continue
                        cur = st.vals.get(place[0])
                        # (the binding it captured - not what that binding's
                        # value holds a handle of, which stays where it is)
                        cty = self.fn.vars[place[0]].ty
                        if cty is not None and cty[0] == "named" and cty[1] in getattr(self.prog, "thread_share", ()):
                            # a handle whose copy is a share of one object
                            # two threads may use: the closure has a share
                            # of its own, both sides keep theirs (§6.5)
                            continue
                        if l in self.cap_loans and not place[1] and cur is not None and cur.own in ("O", "P"):
                            self.move_out(st, place[0], line)
        # a closure the callee may run does, at this call, what its body does
        # to its captures (MEMORY.md §2.11); a callee nothing says that of
        # may run any closure it is handed
        inv = sm.get("invokes")
        gone = set(sm.get("detaches", ()))
        for k, av in enumerate(avs):
            # (one another thread runs took its captures with it, above)
            if k not in gone and (inv is None or k in inv) and self.closures_in(av):
                self.run_closures(st, av, line, f"{name}: the closure in argument {k + 1}")
                for a in av.alias:
                    if a[0] in self.pidx:
                        self.s_invokes.add(self.pidx[a[0]])
        # …and what the callee hands that closure of its other arguments
        for (k, i, j, path) in sm.get("cloargs", ()):
            if k < len(avs) and j < len(ops) and ops[j][0] == "v":
                for _, fname in self.closures_in(avs[k]):
                    pl = [None] * (i + 1)
                    pl[i] = (ops[j][1], ops[j][2] + tuple(path))
                    self.closure_arg_effects(st, fname, pl, line)
        # stores into arguments
        for (j, dpath, k, path, kind) in sm["stores"]:
            if j >= len(ops) or k >= len(ops) or ops[j][0] != "v":
                continue
            src = avs[k]
            dpath = tuple(dpath)
            if kind == "value":
                op = ops[k]
                sv = self.fn.vars[op[1]] if op[0] == "v" else None
                if (src.own == "O" and op[0] == "v" and not op[2] and sv.kind != "temp"
                        and sv.ty is not None and sv.ty[0] == "s"):
                    # an owned raw string in a binding: what keeps it holds a
                    # view of the binding's buffer (MEMORY.md §2.13)
                    add = {(dpath, self.loan(st, (site, "sv", j, k), (op[1], ()), "view"))}
                elif src.own in ("O", "P") and op[0] == "v" and not op[2]:
                    self.fresh_string_kept(st, op, src, line, f"{name}, which keeps it")
                    moved = self.move_out(st, op[1], line)
                    moved = self.reroot(st, moved, ops[j][1], ops[j][2] + dpath)
                    add = hroot(self.closure_owned(moved.held), dpath)
                elif src.own == "L":
                    ty = self.ty_of_place((op[1], op[2])) if op[0] == "v" else None
                    if (ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES and not src.call
                            and op[0] == "v" and not op[2] and self.fn.vars[op[1]].mut
                            and self.fn.vars[op[1]].kind == "local" and src.alias
                            and all(not a[1] and st.vals.get(a[0]) is not None and st.vals[a[0]].own == "O"
                                    and self.fn.vars[a[0]].kind == "local" for a in src.alias)
                            and self.take_payload(st, src, line)):
                        # a `: ~` cursor of a binding hands on the value it
                        # copies the handle of: the binding is moved through
                        # it (MEMORY.md §7.6), and the cursor reads the
                        # value where it went
                        add = hroot(src.held, dpath)
                        went = (ops[j][1], ops[j][2] + dpath)
                        st.vals[op[1]] = AV("L", {self.loan(st, (site, "cm", j, k), went, "handle")}, {went},
                                            src.held)
                    elif ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES and self.T.copyable(ty):
                        # a lend stored as an owner is copied, with the views it holds
                        add = hroot(src.held, dpath)
                    elif (ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES and not src.call
                          and src.alias and all(not a[1] for a in src.alias)
                          and self.take_payload(st, src, line)):
                        # a second name of an owner (a parameter renamed, a
                        # cursor of a binding) kept by value: the owner is
                        # taken over through it (MEMORY.md §7.6)
                        add = hroot(src.held, dpath)
                    else:
                        if ty is not None and self.T.owning(ty) and ty[0] not in VIEW_TYPES:
                            self.err(line, f"{name} keeps a borrowed value that would have to be copied, "
                                           f"and it cannot be copied")
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
        # an owned temporary the callee hands back whole leaves with the
        # result: the result owns it (MEMORY.md §1, Temporaries)
        whole = set()
        if sm["res"] == "lent":
            whole = {k for (k, path, kind) in sm["lends"] if not path and k < len(ops)
                     and ops[k][0] == "v" and not ops[k][2] and self.fn.vars[ops[k][1]].kind == "temp"
                     and avs[k].own == "O"
                     # (a handle, or a raw string handed back as the raw
                     # string it is: an owned one is its own buffer)
                     and (kind == "handle" or (kind == "view" and dest_vid is not None
                                               and self.fn.vars[ops[k][1]].ty is not None
                                               and self.fn.vars[ops[k][1]].ty[0] == "s"
                                               and self.fn.vars[dest_vid].ty == self.fn.vars[ops[k][1]].ty))}
        # the closure bodies the callee leaves in an argument, and in its result
        for (j, dpath, fname) in sm.get("sclos", ()):
            if j < len(ops) and ops[j][0] == "v":
                self.store_into(st, (ops[j][1], ops[j][2]), {(tuple(dpath), ("clo", fname))})
        for (dpath, fname) in sm.get("rclos", ()):
            held.add((tuple(dpath), ("clo", fname)))
        vcopy = None
        for (dpath, k, path, kind) in sm["rholds"]:
            if k >= len(avs) or (k in whole and kind == "held" and not path and not dpath):
                # (what a temporary handed back whole holds comes with it)
                continue
            dpath = tuple(dpath)
            if kind == "held":
                # (a closure the result keeps copies in what it can, §7.5)
                held |= hroot(self.closure_owned(hsub(avs[k].held, tuple(path))), dpath)
                if not path and not dpath and avs[k].own == "L" and dest_vid is not None:
                    ty = self.fn.vars[dest_vid].ty
                    if ty is not None and ty[0] in VIEW_TYPES:
                        # a copy of a view is that view (MEMORY.md §2.13)
                        vcopy = avs[k]
                elif (not path and not dpath and avs[k].own == "O" and dest_vid is not None
                      and ops[k][0] == "v" and not ops[k][2] and self.fn.vars[ops[k][1]].kind != "temp"
                      and self.fn.vars[dest_vid].ty is not None and self.fn.vars[dest_vid].ty[0] == "s"
                      and self.fn.vars[ops[k][1]].ty == self.fn.vars[dest_vid].ty):
                    # (…and a copy of an owned raw string in a binding is a
                    # view of that binding's buffer)
                    vcopy = AV("L", {self.loan(st, (site, "vc", k), (ops[k][1], ()), "view")},
                               {(ops[k][1], ())}, frozenset())
            else:
                held |= hfrom(avs[k].loans, dpath)
                for a in avs[k].alias:
                    held.add((dpath, self.loan(st, (site, "r", k, dpath), (a[0], a[1] + tuple(path)), kind)))
        if sm["res"] == "own":
            if dest_vid is not None:
                # what the result holds of its own parts (a field viewing a
                # sibling field): views of the result's holder
                for (dpath, path, kind) in sm.get("selfholds", ()):
                    held.add((tuple(dpath), self.loan(st, (site, "self", tuple(dpath)), (dest_vid, tuple(path)), kind)))
            if vcopy is not None:
                return AV("L", vcopy.loans, vcopy.alias, held, True)
            return AV("O", (), (), held)
        if sm["res"] == "lent":
            loans, alias = set(), set()
            if dest_vid is not None:
                self.call_by_fn[dest_vid] = name in self.prog.fns and name not in getattr(self.prog, "trusted", ())
                # (the arguments this call may hand back whole, as written)
                self.call_lent[dest_vid] = [ops[k] for (k, path, kind) in sm["lends"]
                                            if not path and kind == "handle" and k < len(ops)]
            part = False
            for k in whole:
                moved = self.move_out(st, ops[k][1], line)
                loans |= moved.loans
                held |= moved.held
            for (k, path, kind) in sm["lends"]:
                if k >= len(avs) or avs[k].own == "N" or (k in whole and not path):
                    continue
                av = avs[k]
                if kind == "held":
                    # what the argument holds, handed back as the value itself
                    loans |= hloans(hsub(av.held, tuple(path)))
                    continue
                if kind == "handle" and not path and k in sm["consumes"] and k not in whole:
                    # an argument the callee took over and hands back as it
                    # is: the caller's own again, holding what it held
                    # (MEMORY.md §7.5, agora #463)
                    held |= av.held
                    part = True
                    continue
                if (kind == "handle" and path and "*" not in path and ops[k][0] == "v" and not ops[k][2]
                        and av.own == "O" and self.fn.vars[ops[k][1]].kind == "temp"):
                    # a part of an owned temporary the callee hands back - a
                    # field, a payload: not an element of its buffer - is
                    # taken out of it: the result owns the part, the rest
                    # goes with the temporary (MEMORY.md §1, Temporaries)
                    held |= hsub(av.held, tuple(path))
                    st.gone = st.gone | {(ops[k][1], tuple(path))}
                    part = True
                    continue
                loans |= av.loans
                for a in av.alias:
                    pl = (a[0], (a[1] + tuple(path))[:PATH_MAX])
                    alias.add(pl)
                    loans.add(self.loan(st, (site, "l", k), pl, kind))
                held |= hsub(av.held, tuple(path))
            if whole or part:
                # (its own on the calls that handed a temporary back, a lend
                # of the other arguments on the rest: owned per call)
                return AV("O", loans, alias, held)
            dty = self.fn.vars[dest_vid].ty if dest_vid is not None else None
            if dty is not None and dty[0] in VIEW_TYPES:
                # a view handed back out of where it was kept (an element
                # that is a slice, a raw string) is that view: it points
                # where the kept one points
                kept = self.view_value(frozenset((hp, l) for hp, l in held if not hp))
                if kept.own == "L":
                    loans |= kept.loans
                    alias |= kept.alias
                    held = {(hp, l) for hp, l in held if hp}
            if not loans and not alias:
                return AV("N", (), (), held)
            if sm.get("mixed") and dest_vid is not None:
                self.call_mixed.add(dest_vid)
            return AV("L", loans, alias, held, call=True)
        return NONE

    def handover(self, st, place):
        """A store replacing a place whose old value a binding reads - the
        place itself, or a part of it - hands that old value over to the
        binding (MEMORY.md §7.6, agora #265): it owns it from here on.  A
        binding that owned its value on other paths already (a join) owns
        it on every path then."""
        for vid, av in list(st.vals.items()):
            if av.own not in ("L", "O") or not av.alias or self.fn.vars[vid].kind == "temp":
                continue
            # (the place itself, or the payload of an option or a result
            # that is the place - agora #170: not a field, an enum's
            # payload or an element, which go with the value replaced)
            if any(a[0] != place[0] or not prefix(place[1], a[1])
                   or a[1][len(place[1]):] not in ((), ("#T0",), ("#F0",)) for a in av.alias):
                continue
            if av.own == "O" and not av.loans:
                continue
            ty = self.fn.vars[vid].ty
            if ty is None or ty[0] in VIEW_TYPES or ty[0] == "closure":
                continue
            keep = {l for l in av.loans if self.loans.get(l, (None,))[0] not in av.alias}
            st.vals[vid] = AV("O", keep, frozenset(), av.held)

    def take_payload(self, st, av, line, direct=True):
        """A value read in place out of what owns it - a binding a cursor or
        a join names, a field, an element, a payload - is taken out of its
        owner when it is consumed: the owner (or that part of it) is moved,
        on some paths only when the value may be one of several."""
        if not av.alias:
            return False
        roots = []
        for vid, path in av.alias:
            root = st.vals.get(vid)
            if root is None or root.own not in ("O", "P"):
                return False
            roots.append((vid, path, root))
        sure = len(roots) == 1
        for vid, path, root in roots:
            # (an element taken leaves its slot empty: what was lent out of
            # the elements before ends, as after a vec_remove - §2.5. A
            # field or a payload taken out leaves the rest of its value as
            # it was: only what was lent out of the part itself ends.)
            part = bool(path) and path[-1] != "*"
            self.effect(st, (vid, path), "take" if part else "replace", line)
            if root.own == "P" and not (path and self.fn.modes[self.pidx[vid]] == "inout"):
                # (a part taken out of an `inout` parameter is a change to
                # the caller's binding, which stays the caller's)
                self.s_consumes.add(self.pidx[vid])
            if not path:
                st.vals[vid] = AV("M" if sure else "X")
            elif "*" not in path and direct:
                # the field is moved where it lives: it, what is under it
                # and the value as a whole are not read until it is given a
                # value again (§2.1). Taken through a binding of it, the
                # field is left empty, and an empty String or Vec is one.
                st.gone = st.gone | {(vid, path)}
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

    # -- closures (MEMORY.md §2.11, §7.5) -----------------------------------------
    def make_closure(self, st, rv, line):
        """A closure literal holds what it captures: a copy of the handle of
        each value captured, and the views those hold.  What it may run is
        its body: `('clo', F)` beside its captures."""
        _, fname, ops, site = rv
        held = {(("^f",), ("clo", fname))}
        body = self.prog.fns.get(fname)
        sm = self.summ.get(fname) or {}
        # the captures the body hands back a view of
        vback = ({k for (k, _, kind) in sm.get("lends", ()) if kind == "view"}
                 | {k for (_, k, _, kind) in sm.get("rholds", ()) if kind == "view"})
        for i, op in enumerate(ops):
            fp = (f"^{i}",)
            byref = body is not None and i < len(body.params) and getattr(body.vars[body.params[i]], "byref", False)
            if byref and op[0] == "v":
                # taken by pointer (a `: ~` binding the body assigns): the
                # closure points into this frame (MEMORY.md §2.3) - at the
                # binding, whatever value it holds when the body runs: it
                # reads nothing where it is made, and has no handle of the
                # value that a new one would end
                held.add((fp, self.loan(st, (site, i, "ref"), (op[1], op[2]), "ref")))
                continue
            av = self.read(st, op, line, (site, i), f"capture {i + 1}")
            if av.own == "N":
                # (a number, a string literal: nothing a view could outlive)
                continue
            if i in vback:
                # a view a closure hands back may point into its arguments,
                # which the call follows, never into what it captured (§7.5)
                self.err(line, "a closure hands back a view of what it captured")
            cty = self.ty_of_place((op[1], op[2])) if op[0] == "v" else None
            if av.own in ("O", "P") and op[0] == "v" and cty is not None and cty[0] == "closure":
                # a captured closure is a copy of it: the new closure holds
                # what that one holds, and no handle of where it sits
                held |= hroot(av.held, fp)
            elif av.own in ("O", "P") and op[0] == "v":
                lid = self.loan(st, (site, i), (op[1], op[2]), "handle")
                self.cap_loans.add(lid)
                held.add((fp, lid))
                held |= hroot(av.held, fp)
            else:
                # (a captured view, or a lend: the closure reaches what it
                # borrows)
                self.cap_loans |= av.loans
                held |= hfrom(av.loans, fp) | hroot(av.held, fp)
        return AV("O", (), (), held)

    def rehome(self, st, rv, dest):
        """A temporary moved into a binding: what was lent out of the
        temporary is lent out of the binding from here on."""
        if not rv or rv[0] != "use" or rv[1][0] != "v" or rv[1][2]:
            return
        src = rv[1][1]
        cur = st.vals.get(src)
        if self.fn.vars[src].kind != "temp" or cur is None or cur.own != "M":
            return
        sub = {}
        for vid, av in st.vals.items():
            for l in av.loans | hloans(av.held):
                if l in self.loans and self.loans[l][0][0] == src and l not in sub:
                    place, kind = self.loans[l]
                    nl = ("rh", l, dest)
                    self.loans[nl] = ((dest, place[1]), kind)
                    sub[l] = nl
        if not sub:
            return
        for vid, av in list(st.vals.items()):
            if not (av.loans & sub.keys() or hloans(av.held) & sub.keys()):
                continue
            st.vals[vid] = AV(av.own, {sub.get(l, l) for l in av.loans},
                              {(dest, a[1]) if a[0] == src else a for a in av.alias},
                              {(hp, sub.get(l, l)) for hp, l in av.held}, av.call)
        st.dead = frozenset(st.dead) - set(sub.values())

    def note_fresh(self, vid, rv, new):
        """`vid` was given `new`: a value of its own that is no `None`?"""
        if new.own not in ("O", "P") or new.loans:
            return
        if rv[0] == "use" and rv[1][0] == "v" and not rv[1][2]:
            if rv[1][1] in self.var_fresh:
                self.var_fresh.add(vid)
            return
        if rv[0] == "agg" and self.temp_none.get(vid):
            return
        self.var_fresh.add(vid)

    def closure_moved_into(self, st, rv, dest):
        """`= keep f`, `: g f`: a closure binding handed to another binding
        gives it its environment and stays a borrow of it - readable while
        that binding holds the value (MEMORY.md §7.5, agora #835)."""
        if not rv or rv[0] != "use" or rv[1][0] != "v" or rv[1][2]:
            return
        src = rv[1][1]
        v = self.fn.vars[src]
        cur, d = st.vals.get(src), st.vals.get(dest)
        if (v.kind == "temp" or v.ty is None or v.ty[0] != "closure" or cur is None or cur.own != "M"
                or d is None or d.own != "O" or self.fn.vars[dest].kind == "temp"):
            return
        st.vals[src] = AV("L", {self.loan(st, ("clomv", src, dest), (dest, ()), "handle")}, {(dest, ())}, d.held)

    def closure_takes_over(self, st, av, line, direct=False):
        """A closure that leaves the frame it was made in owns a capture it
        cannot copy: the binding it captured moves into its environment,
        and the frame no longer releases it (MEMORY.md §7.5, h240)."""
        bases = {hp[:-1]: l[1] for hp, l in av.held
                 if isinstance(l, tuple) and len(l) == 2 and l[0] == "clo" and hp and hp[-1] == "^f"}
        if not bases:
            return av
        held = set(av.held)
        for hp, l in av.held:
            if (not hp or hp[:-1] not in bases or not hp[-1].startswith("^") or hp[-1] == "^f"
                    or l not in self.cap_loans or l not in self.loans or self.loans[l][1] != "handle"):
                continue
            place = self.loans[l][0]
            v = self.fn.vars[place[0]]
            # (one its body hands on to a consumer - or, for a closure
            # handed back as it is written, a struct with a destructor of
            # its own that it only reads, h224. An option, a container or a
            # raw string it only reads stays the frame's, and the closure
            # may not outlive it: agora #463, h141.)
            consumed = int(hp[-1][1:]) in (self.summ.get(bases[hp[:-1]]) or {}).get("consumes", ())
            plain = (direct and v.ty is not None and v.ty[0] == "named"
                     and v.ty[1] not in getattr(self.prog, "handle_elem", ()))
            if not consumed and not plain:
                continue
            cur = st.vals.get(place[0])
            if (place[1] or v.kind != "local" or cur is None or cur.own != "O" or v.ty is None
                    or v.ty[0] == "closure" or self.T.copyable(v.ty)):
                continue
            moved = self.move_out(st, place[0], line)
            self.moved_from = None
            held.discard((hp, l))
            held |= hroot(moved.held, hp)
        return AV(av.own, av.loans, av.alias, held, av.call)

    def closure_owned(self, held):
        """What a closure kept by an owner - stored into a container, a
        field or a literal, or handed back - holds: it copies in every
        capture it held a handle of that has a copy (§7.5), so only what it
        cannot copy, the views its captures hold and its pointers into the
        frame still borrow."""
        bases = [(hp[:-1], l[1]) for hp, l in held
                 if isinstance(l, tuple) and len(l) == 2 and l[0] == "clo" and hp and hp[-1] == "^f"]
        if not bases:
            return held
        # (a closure captured by another keeps the handles it holds as they
        # are: no owner copies them in - agora #161)
        bases = [(b, f) for b, f in bases
                 if not any(len(o) < len(b) and b[:len(o)] == o and b[len(o)].startswith("^") for o, _ in bases)]
        drop = set()
        add = set()
        shared = getattr(self.prog, "shared", ())
        for base, fname in bases:
            body = self.prog.fns.get(fname)
            if body is None:
                continue
            n = len(base)
            for hp, l in held:
                if hp[:n] != base or len(hp) != n + 1 or not hp[n].startswith("^") or hp[n] == "^f":
                    continue
                if l not in self.loans or self.loans[l][1] != "handle":
                    continue
                i = int(hp[n][1:])
                cty = body.vars[body.params[i]].ty if i < len(body.params) else None
                if cty is not None and (self.T.copyable(cty) or cty[0] == "closure"):
                    # (a captured closure is copied as any closure kept is)
                    drop.add((hp, l))
                    if cty[0] == "named" and cty[1] in shared:
                        # its copy of a shared handle is a share: it ends
                        # with nothing, and still reaches the one payload
                        sl = ("share", l)
                        self.loans[sl] = (self.loans[l][0], "share")
                        add.add((hp, sl))
        return (frozenset(held) - drop) | add

    def closures_in(self, av):
        """The closure bodies a value may run, with where its captures sit."""
        return [(hp[:-1], l[1]) for hp, l in av.held
                if isinstance(l, tuple) and len(l) == 2 and l[0] == "clo" and hp and hp[-1] == "^f"]

    def run_closures(self, st, av, line, what):
        """Running a closure reads every capture and does what its body does
        to them."""
        self.check_live(st, AV("N", held=av.held), line, what, held=True)
        for base, fname in self.closures_in(av):
            sm = self.summ.get(fname)
            fn = self.prog.fns.get(fname)
            if sm is None or fn is None:
                continue
            ncap = getattr(fn, "ncap", 0)
            n = len(base)
            caps = {}
            for hp, l in av.held:
                if hp[:n] == base and len(hp) == n + 1 and hp[n].startswith("^") and hp[n] != "^f" and l in self.loans:
                    caps.setdefault(int(hp[n][1:]), []).append(self.loans[l][0])
            for (k, path, eff) in sm["effects"]:
                if k < ncap:
                    for place in caps.get(k, ()):
                        self.effect(st, (place[0], place[1] + tuple(path)), eff, line)
            for k in sm["consumes"]:
                if k < ncap:
                    for place in caps.get(k, ()):
                        # the body releases its capture when it runs
                        self.effect(st, place, "replace", line)
                        cur = st.vals.get(place[0])
                        if cur is not None and cur.own in ("O", "P") and not place[1]:
                            if cur.own == "P":
                                self.s_consumes.add(self.pidx[place[0]])
                            st.vals[place[0]] = AV("X")

    def call_closure(self, st, rv, line):
        """A call through a closure value: its arguments are lent, its result
        is its caller's own (§7.5)."""
        _, ops, site = rv
        cav = self.read(st, ops[0], line, (site, 0), "the closure")
        avs = []
        for i, op in enumerate(ops[1:]):
            avs.append(self.read(st, op, line, (site, i + 1), f"argument {i + 1} of the closure"))
        self.run_closures(st, cav, line, "the closure called here")
        known = self.closures_in(cav)
        # what the body does to its parameters it does to these arguments
        for _, fname in known:
            self.closure_arg_effects(st, fname, [(op[1], op[2]) if op[0] == "v" else None for op in ops[1:]], line)
            # …and a closure it is handed and runs does, here, what its own
            # body does: to what it captured, and to the arguments the body
            # hands it (the body's `invokes` / `cloargs`)
            sm = self.summ.get(fname)
            body = self.prog.fns.get(fname)
            if sm is None or body is None:
                continue
            ncap = getattr(body, "ncap", 0)
            for k in sm.get("invokes", ()):
                i = k - ncap
                if 0 <= i < len(avs) and self.closures_in(avs[i]):
                    self.run_closures(st, avs[i], line, f"the closure in argument {i + 1}")
            for (k, pi, j, path) in sm.get("cloargs", ()):
                i, src = k - ncap, j - ncap
                if 0 <= i < len(avs) and 0 <= src < len(avs) and ops[1 + src][0] == "v":
                    for _, f2 in self.closures_in(avs[i]):
                        pl = [None] * (pi + 1)
                        pl[pi] = (ops[1 + src][1], ops[1 + src][2] + tuple(path))
                        self.closure_arg_effects(st, f2, pl, line)
        if not known and getattr(self.fn, "is_closure", False):
            # inside a closure, a closure it was handed is the caller's:
            # what this one captured the caller's may have captured too, and
            # running it may grow or clear it (MEMORY.md §2.11)
            for vid in self.fn.params[:getattr(self.fn, "ncap", 0)]:
                self.effect(st, (vid, ()), "realloc", line)
                self.effect(st, (vid, ()), "drop", line)
        if not known:
            roots = {self.pidx[a[0]] for a in cav.alias if a[0] in self.pidx}
            if ops[0][0] == "v" and ops[0][1] in self.pidx:
                roots.add(self.pidx[ops[0][1]])
            self.s_invokes |= roots
            # a closure the caller chose is run on these arguments: which of
            # this function's parameters they are parts of is its summary's
            for k in roots:
                for i, av in enumerate(avs):
                    op = ops[1 + i]
                    places = set(av.alias)
                    if op[0] == "v":
                        places.add((op[1], op[2]))
                    for a in places:
                        if a[0] in self.pidx:
                            self.s_cloargs.add((k, i, self.pidx[a[0]], a[1][:3]))
        return AV("O")

    def closure_capture_effects(self, av):
        """(place, effect) for what the closures a value may run do to what
        they captured."""
        out = []
        for base, fname in self.closures_in(av):
            sm = self.summ.get(fname)
            fn = self.prog.fns.get(fname)
            if sm is None or fn is None:
                continue
            ncap = getattr(fn, "ncap", 0)
            n = len(base)
            for (k, path, eff) in sm["effects"]:
                if k >= ncap:
                    continue
                for hp, l in av.held:
                    if hp[:n] == base and len(hp) == n + 1 and hp[n] == f"^{k}" and l in self.loans:
                        place = self.loans[l][0]
                        out.append(((place[0], place[1] + tuple(path)), eff))
        return out

    def closure_arg_effects(self, st, fname, places, line):
        """The effects of closure body `fname` on its own parameters, applied
        to the places it is called with (None: not a place)."""
        sm = self.summ.get(fname)
        fn = self.prog.fns.get(fname)
        if sm is None or fn is None:
            return
        ncap = getattr(fn, "ncap", 0)
        for (k, path, eff) in sm["effects"]:
            i = k - ncap
            if 0 <= i < len(places) and places[i] is not None:
                self.effect(st, (places[i][0], places[i][1] + tuple(path)), eff, line)

    def exit_drops(self, st, line, keep=None):
        """A function's exit releases what its frame still owns, newest
        first: the drop of a value whose destructor may read its views is a
        use of them (MEMORY.md §2.14)."""
        udrop = getattr(self.prog, "udrop", ())
        if st.bottom or not udrop:
            return
        for vid in sorted(st.vals, reverse=True):
            av = st.vals[vid]
            v = self.fn.vars[vid]
            if av.own != "O" or v.kind == "param" or vid == keep:
                continue
            if av.held and v.ty is not None and v.ty[0] == "named" and v.ty[1] in udrop:
                self.check_live(st, AV("N", held=av.held), line, f"the drop of {v.name}", held=True)
            self.effect(st, (vid, ()), "replace", line)
            st.vals[vid] = AV("D")

    def params_hold_locals(self, st, line):
        """Storage the caller holds - a parameter, or what one points into -
        may not be left holding a view of this frame's own values."""
        if st.bottom:
            return
        for vid in self.pidx:
            av = st.vals.get(vid)
            if av is None:
                continue
            for hp, l in av.held:
                # (live or ended: a view of a local that ended inside the
                # function is one the caller's storage still holds)
                if l in self.loans:
                    v = self.fn.vars[self.loans[l][0][0]]
                    if v.kind != "param" and self.loans[l][1] != "share":
                        self.err(line, f"{self.vname(vid)} is the caller's, and goes back holding a view of {v.name}")
                        return

    def run_defers(self, st):
        """A function's exit runs the `;` blocks armed on the way, newest
        first."""
        if st.bottom or not st.defers:
            return st
        pending = st.defers
        st.defers = ()
        for d in reversed(pending):
            st = self.run(st, self.defer_bodies[d])
            if st.bottom:
                break
        return st

    # -- rvalues ---------------------------------------------------------------
    def rvalue(self, st, rv, line, dest_depth, dest_ty, what, copy_ok=False, lend_owner=lambda vid: False,
               dest_vid=None, named=False):
        k = rv[0]
        if k == "use":
            return self.transfer(st, rv[1], line, ("use", id(rv)), dest_depth, dest_ty, what, copy_ok=copy_ok,
                                 lend_owner=lend_owner, dest_vid=dest_vid, named=named)
        if k == "call":
            av = self.apply_call(st, rv, line, dest_vid)
            if av.own == "L" and dest_ty is not None and dest_ty[0] == "closure":
                # a closure a call hands back is its caller's own copy: it
                # holds what the lent one holds, and is no borrow of where
                # that one sat (MEMORY.md §7.5)
                av = AV("O", (), (), av.held)
            if av.own == "L" and self.local_depth(AV("L", av.loans, av.alias)) > dest_depth:
                if copy_ok and dest_ty is not None and self.T.copyable(dest_ty) and not self.T.is_scalar(dest_ty):
                    return AV("O")
                self.err(line, f"{what}: a view of a value released before its holder escapes")
            return av
        if k == "agg":
            _, ty, variant, ops, site = rv
            if dest_vid is not None:
                self.temp_none[dest_vid] = variant == "F" and ty is not None and ty[0] == "opt"
            names = self.agg_paths(ty, variant, len(ops))
            held = set()
            lent = {}
            nc_loans, nc_alias = set(), set()
            for i, op in enumerate(ops):
                fty = self.ty_of_field(ty, variant, i)
                fp = (names[i],)
                cur = st.vals.get(op[1]) if op[0] == "v" and not op[2] else None
                if (dest_vid is not None and self.fn.vars[dest_vid].kind == "temp" and cur is not None
                        and cur.own == "O" and self.fn.vars[op[1]].kind == "local"
                        and fty is not None and fty[0] not in VIEW_TYPES and fty[0] != "closure"):
                    # (a closure binding is copied into the literal: below)
                    # a literal that is a statement's temporary shows its
                    # consumer the bindings it names: they move into it only
                    # where the literal itself is taken (stored, handed to a
                    # consumer, handed back) - a callee that borrows it
                    # leaves them their owners' (MEMORY.md §7.6, h693)
                    av = self.read(st, op, line, (site, i), f"field {i + 1}")
                    held.add((fp, self.loan(st, (site, i, "lit"), (op[1], ()), "handle")))
                    held |= hroot(av.held, fp)
                    lent[names[i]] = op[1]
                    continue
                if cur is not None:
                    self.fresh_string_kept(st, op, cur, line, "a field")
                if (cur is not None and cur.own == "L" and not cur.call and self.fn.vars[op[1]].mut
                        and self.fn.vars[op[1]].kind == "local" and cur.alias and dest_vid is not None
                        and fty is not None and fty[0] not in VIEW_TYPES and fty[0] != "closure" and self.T.owning(fty)
                        and all(not a[1] and st.vals.get(a[0]) is not None and st.vals[a[0]].own == "O"
                                and self.fn.vars[a[0]].kind == "local" for a in cur.alias)
                        and self.take_payload(st, cur, line)):
                    # a `: ~` cursor of a binding hands on the value it
                    # copies the handle of: the binding is moved into the
                    # literal through it, and the cursor reads it there
                    held |= hroot(cur.held, fp)
                    went = (dest_vid, fp)
                    st.vals[op[1]] = AV("L", {self.loan(st, (site, i, "cm"), went, "handle")}, {went}, cur.held)
                    continue
                self.moved_from = None
                av = self.transfer(st, op, line, (site, i), dest_depth, fty, f"field {i + 1}", stored=True)
                if dest_vid is not None:
                    av = self.reroot(st, av, dest_vid, (names[i],))
                if av.own == "L":
                    if (fty is not None and self.T.owning(fty) and fty[0] not in VIEW_TYPES
                            and not self.T.copyable(fty)):
                        dv = self.fn.vars[dest_vid] if dest_vid is not None else None
                        # (a statement's temporary, or the unnamed binding a
                        # `\` try hands its failure on in)
                        if (dv is not None and (dv.kind == "temp" or dv.name.startswith("%t")) and not av.call
                                and av.alias and all(a[0] in self.pidx and a[1] for a in av.alias)):
                            # a part of a parameter, read in place: the
                            # literal is a lend of the caller's value, good
                            # to hand back as it is and nothing else
                            # (MEMORY.md §7.6, agora #200)
                            nc_loans |= av.loans
                            nc_alias |= av.alias
                            self.lit_nocopy[dest_vid] = i + 1
                        elif (not av.call and av.alias and op[0] == "v" and not op[2] and op[1] in self.slot_vars
                              and all(st.vals.get(a[0]) is not None and st.vals[a[0]].own == "O" for a in av.alias)
                              and self.take_payload(st, av, line)):
                            # the payload of a library getter's option over
                            # one of this frame's containers: a slot, which
                            # is emptied, and the literal owns what was in
                            # it (MEMORY.md §7.6)
                            held |= hroot(av.held, fp)
                            continue
                        else:
                            self.err(line, f"field {i + 1}: a borrowed value would have to be copied here, "
                                           f"and it cannot be copied")
                    if fty is not None and self.T.owning(fty) and fty[0] not in VIEW_TYPES and self.T.copyable(fty):
                        dv = self.fn.vars[dest_vid] if dest_vid is not None else None
                        if (dv is not None
                                and (dv.kind == "temp" or dv.name.startswith("%t")) and not av.call
                                and av.alias and all(a[0] in self.pidx and a[1] for a in av.alias)):
                            # a part of a parameter, read in place: handed
                            # back as it is, the literal is a lend of the
                            # caller's value (no copy is made); taken by
                            # anything else, it is copied there
                            nc_loans |= av.loans
                            nc_alias |= av.alias
                            self.lit_lendcopy.add(dest_vid)
                        # a lend stored into an owning field is copied: the
                        # copy holds the views the value holds (§2.13)
                        held |= hroot(av.held, fp)
                        continue
                    held |= hfrom(av.loans, fp)
                held |= hroot(self.closure_owned(av.held), fp)
            if lent:
                self.agg_lends[dest_vid] = lent
            if nc_loans:
                return AV("L", nc_loans, nc_alias, held)
            return AV("O", (), (), held)
        if k == "closure":
            return self.make_closure(st, rv, line)
        if k == "callind":
            av = self.call_closure(st, rv, line)
            if dest_ty is not None and self.T.is_scalar(dest_ty):
                return NONE
            return av
        if k == "scalar":
            for i, op in enumerate(rv[1]):
                self.read(st, op, line, ("sc", id(rv), i))
            return NONE
        if k == "payload":
            _, op, variant, idx = rv
            av = self.read(st, op, line, ("pl", id(rv)), "matched value")
            if av.own == "N":
                return NONE
            if dest_ty is not None and self.T.is_scalar(dest_ty):
                # (a number: a copy, nothing to follow)
                return NONE
            tag = f"#{variant}{idx}"
            sub = hsub(av.held, (tag,))
            pty = self.ty_of_field(self.fn.vars[op[1]].ty if op[0] == "v" and not op[2] else None, variant, idx)
            if op[0] == "v" and not op[2] and self.fn.vars[op[1]].kind == "temp" and av.own == "O":
                return self.lent_part(AV("O", (), (), sub))
            if pty is not None and pty[0] in VIEW_TYPES:
                v = self.view_value(sub)
                return AV("L", v.loans | av.loans, v.alias, frozenset()) if v.own == "L" else NONE
            loans, alias = set(av.loans), set()
            for a in av.alias:
                aty = self.ty_of_place(a)
                wrapped = (aty is not None and aty[0] not in ("opt", "res")
                           and not (aty[0] == "named" and aty[1] in self.prog.enums))
                # (an option a callee made around a lend of an element -
                # `vec_get` - is no place of its own: its payload is the
                # element)
                pl = a if wrapped else (a[0], (a[1] + (tag,))[:PATH_MAX])
                alias.add(pl)
                loans.add(self.loan(st, ("pl", id(rv), pl), pl, "handle"))
            # (the payload of what a function of the program lent is that
            # call's lend still: not a slot a consumer may empty, as the
            # payload of a library getter's option is)
            lent_by_fn = (av.call and op[0] == "v" and not op[2] and self.fn.vars[op[1]].kind == "temp"
                          and self.call_by_fn.get(op[1], False))
            if (dest_vid is not None and av.call and not lent_by_fn and op[0] == "v" and not op[2]
                    and self.fn.vars[op[1]].kind == "temp" and alias and all("*" in a[1] for a in alias)):
                self.slot_vars.add(dest_vid)
            return AV("L", loans, alias, sub, lent_by_fn)
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

    def defer_reads(self, st):
        """The variables the `;` blocks armed so far name."""
        out = set()
        for d in st.defers:
            if d not in self.defer_vars:
                found = set()

                def walk(x):
                    if isinstance(x, tuple) and len(x) == 3 and x[0] == "v" and isinstance(x[1], int):
                        found.add(x[1])
                    elif isinstance(x, (tuple, list)):
                        for y in x:
                            walk(y)
                walk(self.defer_bodies[d])
                self.defer_vars[d] = found
            out |= self.defer_vars[d]
        return out

    def scope_end(self, st, stmts, line):
        if st.bottom:
            return st
        declared = [s[1] for s in stmts if s[0] == "let"]
        # a binding a `;` block armed here may read is released after the
        # chain has run, at the function's exit: not where its scope ends
        # (MEMORY.md §7.2, "values registered before a defer")
        kept = self.defer_reads(st) if st.defers else ()
        for vid in reversed(declared):
            av = st.vals.get(vid)
            if av is None or vid in kept:
                continue
            if av.own == "O":
                vty = self.fn.vars[vid].ty
                if av.held and vty is not None and vty[0] == "named" and vty[1] in getattr(self.prog, "udrop", ()):
                    # its destructor may read the views it holds: its drop
                    # is a use of what they point into (MEMORY.md §2.14)
                    self.check_live(st, AV("N", held=av.held), line, f"the drop of {self.vname(vid)}", held=True)
                self.effect(st, (vid, ()), "replace", line)
            # (the binding itself is gone: what points at it ends)
            self.effect(st, (vid, ()), "end", line)
            if av.own != "M":
                st.vals[vid] = AV("D")
        # a loan nothing holds any more is no fact about a later round or a
        # later use of its site: only what some value still needs stays ended
        st.dead = st.dead & (self.all_loans(st) | self.walking)
        if st.gone:
            st.gone = frozenset(g for g in st.gone if g[0] not in declared)
        return st

    def stmt(self, st, s):
        k = s[0]
        if k == "let":
            _, vid, rv, ln = s
            v = self.fn.vars[vid]
            if rv is not None and v.kind == "temp":
                # (a call whose summary says its result is its own)
                self.temp_fresh[vid] = rv[0] == "call" and self.summary(rv[1])["res"] == "own" and not self.summary(rv[1])["rholds"]
            if rv is None:
                st.vals[vid] = AV("U")
            else:
                # `: ~ T c x` is a cursor: it borrows the owner x
                new = self.rvalue(st, rv, ln, v.depth, v.ty, v.name, dest_vid=vid,
                                  lend_owner=(lambda x: True) if v.mut else (lambda x: False))
                if (not v.mut and v.kind == "local" and rv[0] == "use" and rv[1][0] == "v" and not rv[1][2]
                        and self.fn.vars[rv[1][1]].kind == "temp" and not new.call and new.alias
                        and (new.own == "L" or (new.own == "O" and new.loans))
                        and v.ty is not None and v.ty[0] not in VIEW_TYPES and v.ty[0] != "closure"
                        and not self.T.is_scalar(v.ty)):
                    # a `?` / `??` (or a value block) that selects among
                    # owners moves the one it selects into the binding, on
                    # the paths that select it (MEMORY.md §2.2)
                    # - owners of this frame that live no longer than the
                    # binding: a parameter is the caller's, and a binding of
                    # an inner scope is a second name of an outer owner
                    roots = [st.vals.get(a[0]) for a in new.alias]
                    if (all(r is not None and r.own == "O" for r in roots)
                            and all(self.fn.vars[a[0]].depth >= v.depth for a in new.alias)
                            and self.take_payload(st, new, ln)):
                        new = AV("O", (), (), new.held)
                if (new.own == "L" and v.kind == "local" and rv[0] == "use" and rv[1][0] == "v" and not rv[1][2]
                        and rv[1][1] in self.call_mixed and v.ty is not None and v.ty[0] not in VIEW_TYPES):
                    # what the call handed back is the caller's own on the
                    # calls that made it fresh: the binding owns it there
                    # and releases it, and borrows on the others (owned per
                    # call, MEMORY.md §7.6 "Call results")
                    new = AV("O", new.loans, frozenset(), new.held)
                if (new.own == "L" and new.loans and v.kind != "temp" and v.ty is not None
                        and v.ty[0] not in VIEW_TYPES and self.T.copyable(v.ty)
                        and all(l in self.loans and self.fn.vars[self.loans[l][0][0]].kind == "temp"
                                and self.loans[l][1] == "handle" for l in new.loans)):
                    # a binding of what a call lent out of a temporary: the
                    # temporary ends with the statement, so the binding is
                    # handed a copy (MEMORY.md §7.6, "a lend handed to a
                    # holder that outlives what it borrows")
                    new = AV("O", (), (), new.held)
                st.vals[vid] = self.reroot(st, new, vid)
                self.note_fresh(vid, rv, new)
                self.closure_moved_into(st, rv, vid)
                self.rehome(st, rv, vid)
            return st
        if k == "assign":
            _, (vid, path), rv, ln = s
            v = self.fn.vars[vid]
            cur = st.vals.get(vid)
            ddepth = v.depth if v.kind != "param" else 0
            if not path:
                outer = lambda x: self.fn.vars[x].depth <= v.depth and self.fn.vars[x].blk != vid
                repoint = cur is not None and cur.own == "L"
                # (a lend of something that ends before the target - an inner
                # block's local, an arm's - is copied in: MEMORY.md §7.6,
                # "hands it a value of its own")
                # (…an owner is: a cursor given a lend stays a borrow, of
                # whatever it is pointed at now)
                new = self.rvalue(st, rv, ln, ddepth, v.ty, v.name, copy_ok=not repoint, dest_vid=vid,
                                  named=v.kind != "temp",
                                  lend_owner=outer if v.kind == "temp" else ((lambda x: True) if v.mut and repoint else (lambda x: False)))
                # (…through a join too: `= x ? c x ( f )` - where the join may
                # select the target, its value is copied in, h373)
                own_parts = cur is not None and cur.own in ("O", "P") and new.own in ("L", "O") and any(
                    self.loans.get(l, ((None,),))[0][0] == vid for l in new.loans) and v.kind != "temp"
                if own_parts:
                    # `= o ( f o … )`: o is given (a part of) its own value back
                    # - it keeps owning it; nothing is released (the keep rule)
                    rest = {l for l in new.loans if self.loans.get(l, ((None,),))[0][0] != vid}
                    # (`= o ( f o other )`: the call is handed the binding
                    # itself and another argument, and may hand back either)
                    lent = self.call_lent.get(rv[1][1], ()) if rv[0] == "use" and rv[1][0] == "v" else ()
                    direct = ("v", vid, ()) in lent and any(op != ("v", vid, ()) for op in lent)
                    if rest and new.call and v.ty is not None and (
                            (v.ty[0] in ("opt", "res") and direct) or not self.T.copyable(v.ty)):
                        # which of them a run hands back is not known, so
                        # neither is whether the binding still owns its value.
                        # (A handle is told apart at run time by its buffer.
                        # An option or a result has no such key, and no
                        # binding borrows the call's result to take the old
                        # value over: agora #412, #425.)
                        self.err(ln, f"{v.name} is given back what this call may lend out of itself "
                                     f"or out of another argument")
                    st.vals[vid] = AV(cur.own, () if cur.own == "P" else rest, frozenset(),
                                      cur.held | new.held | (hfrom(rest) if cur.own == "P" else frozenset()))
                    return st
                inside = {(hp, l) for hp, l in new.held if l in self.loans and self.loans[l][0][0] == vid
                          and self.loans[l][1] == "handle"}
                if inside and cur is not None and cur.own in ("O", "P") and new.own == "O" and v.kind != "temp":
                    # `= base ( wrap base )`: the new value holds a handle of
                    # the binding's old one (a closure that captured it). The
                    # old value is kept inside the new: nothing is released
                    # (the keep rule, as for a part handed back)
                    st.vals[vid] = AV(cur.own, new.loans, frozenset(), cur.held | (new.held - inside))
                    return st
                if cur is not None and cur.own in ("O", "P"):
                    self.handover(st, (vid, ()))
                    self.effect(st, (vid, ()), "replace", ln)
                new = self.reroot(st, new, vid)
                if cur is not None and cur.own == "P":
                    held = (new.held | hfrom(new.loans)) if new.own == "L" else new.held
                    st.vals[vid] = AV("P", (), (), held)
                elif cur is not None and cur.own == "O" and new.own == "L" and new.call:
                    # (an owner given a call's lend holds its own copy of
                    # the handle from here on: no longer "what a call lent")
                    st.vals[vid] = AV("L", new.loans, new.alias, new.held)
                else:
                    st.vals[vid] = new
                self.note_fresh(vid, rv, new)
                self.closure_moved_into(st, rv, vid)
                if st.gone:
                    st.gone = frozenset(g for g in st.gone if g[0] != vid)
                return st
            fty = self.ty_of_place((vid, path))
            new = self.rvalue(st, rv, ln, ddepth, fty, self.pname((vid, path)))
            if new.own == "L" and fty is not None and fty[0] == "closure":
                # a closure stored into a field is the field's own copy: it
                # holds what the one it was copied from holds, and is no
                # borrow of where that one sits (MEMORY.md §7.5)
                new = AV("O", (), (), self.closure_owned(new.held))
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
            if st.gone:
                st.gone = frozenset(g for g in st.gone if not (g[0] == vid and prefix(path, g[1])))
            return st
        if k == "eval":
            _, rv, ln = s
            self.rvalue(st, rv, ln, 99, None, "value")
            return st
        if k == "gstore":
            # a module global outlives every frame: it may hold no view of a
            # frame's value, nor of what a caller lent (MEMORY.md §2.13)
            _, gname, rv, ln = s
            av = self.rvalue(st, rv, ln, 99, None, f"the global {gname}")
            if (av.own == "L" and av.loans) or [l for _, l in av.held if l in self.loans]:
                self.err(ln, f"the global {gname} is given a view of a value it outlives")
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
        if k == "defer":
            _, body, ln = s
            self.defer_bodies.append(body)
            st.defers = st.defers + (len(self.defer_bodies) - 1,)
            return st
        if k == "ret":
            _, op, ln = s
            if op is not None:
                before = st.vals.get(op[1]) if op[0] == "v" and not op[2] else None
                av = self.transfer(st, op, ln, ("ret", id(s)), 0, self.fn.ret, "the returned value",
                                   copy_ok=True, is_ret=True)
                self.moved_from = None
                gone = st.vals.get(op[1]) if before is not None else None
                if st.defers and before is not None and gone is not None and gone.own == "M":
                    # the `;` blocks run after the result is made and before
                    # it leaves the frame: they still read the binding it
                    # was made from (MEMORY.md §1)
                    st.vals[op[1]] = before
                    self.ret_watch, self.ret_changed = op[1], False
                    st = self.run_defers(st)
                    self.ret_watch = None
                    if not st.bottom:
                        after = st.vals.get(op[1])
                        if (self.ret_changed or after is None or after.own != before.own
                                or any(g[0] == op[1] for g in st.gone)):
                            # (…read it: a block that releases or changes
                            # it does so to the value the caller was handed)
                            self.err(ln, f"a `;` block releases or changes {self.vname(op[1])}, "
                                         f"which was handed back")
                        st.vals[op[1]] = gone
                else:
                    st = self.run_defers(st)
                self.check_live(st, av, ln, "the returned value", held=True)
                self.params_hold_locals(st, ln)
                self.rets.append((av, st.copy()))
                if av.own in ("O", "P") and not av.loans and not (
                        op[0] == "v" and not op[2] and op[1] not in self.var_fresh):
                    # (a value of its own that holds something: an option's
                    # `None` hands no storage over, nor does a binding that
                    # was only ever given one)
                    self.ret_fresh = True
                self.exit_drops(st, ln)
            else:
                st = self.run_defers(st)
                self.params_hold_locals(st, ln)
                self.exits.append(st.copy())
                self.exit_drops(st, ln)
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
        outer = set(self.walking)
        self.walking |= walk
        for _ in range(12):
            nxt, _ = self._fe_round(head, s, vid, walk, elem_alias, src, body, ln)
            if nxt.key() == head.key():
                break
            head = nxt
        self.final = final
        _, out = self._fe_round(head, s, vid, walk, elem_alias, src, body, ln)
        self.walking = outer
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
            if v.ty is not None and self.T.is_scalar(v.ty):
                st.vals[vid] = NONE
            else:
                # what a parameter's value holds is the caller's to say: one
                # loan stands for it, and the summary hands it on by name
                st.vals[vid] = AV("P", (), (), {((), self.loan(st, ("ph", vid), (-1 - vid, ()), "held"))})
        end = self.run(st, self.fn.body)
        if not end.bottom:
            end = self.run_defers(end)
            self.params_hold_locals(end, self.fn.line)
            self.exits.append(end)
        return self.make_summary()

    def param_loan(self, lid):
        if lid not in self.loans:
            return None
        place, kind = self.loans[lid]
        if place[0] in self.hvid:
            return self.hvid[place[0]], (), "held"
        if place[0] in self.pidx:
            return self.pidx[place[0]], place[1][:3], kind
        return None

    def make_summary(self):
        res = "none"
        lends, rholds = set(), set()
        rclos, sclos = set(), set()

        def clo_path(hp):
            return hp if len(hp) <= 6 else hp[:5] + ("^f",)
        calllends = set()
        for av, _ in self.rets:
            if av.call and av.own == "L":
                # (handed back as a call lent it: not the parameter itself)
                for lid in av.loans:
                    pl = self.param_loan(lid)
                    if pl and pl[2] == "handle":
                        calllends.add(pl[0])
            for hp, l in av.held:
                if isinstance(l, tuple) and len(l) == 2 and l[0] == "clo":
                    # the closure bodies the result may run
                    rclos.add((clo_path(hp), l[1]))
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
        mixed = False
        if res == "own" and lends:
            # its own on some paths, a lend of an argument on others: the
            # caller's result borrows that argument (answered per call,
            # MEMORY.md §7.6 "Call results")
            res = "lent"
        if res == "lent" and self.ret_fresh:
            # (…and is the caller's own on the calls that made it fresh:
            # what holds it releases it there)
            mixed = True
        if self.fn.ret is not None and self.T.is_scalar(self.fn.ret):
            res = "none"
        if res == "lent" and not lends:
            res = "own"
        stores = set()
        left_gone = set()
        for st in [s for _, s in self.rets] + self.exits:
            for (gv, gp) in st.gone:
                if gv in self.pidx and self.fn.modes[self.pidx[gv]] == "inout":
                    # a part taken out of an `inout` parameter and not given
                    # a value again: the caller's binding goes back without it
                    left_gone.add((self.pidx[gv], tuple(gp)[:3]))
            for vid, j in self.pidx.items():
                av = st.vals.get(vid)
                if av is None:
                    continue
                for hp, lid in av.held:
                    if isinstance(lid, tuple) and len(lid) == 2 and lid[0] == "clo":
                        sclos.add((j, clo_path(hp), lid[1]))
                        continue
                    pl = self.param_loan(lid)
                    if pl and not (pl[2] == "held" and pl[0] == j):
                        stores.add((j, hp[:3]) + pl)
        consumes = set(self.s_consumes) | {k for k, m in enumerate(self.fn.modes) if m == "sink"}
        return {"modes": list(self.fn.modes), "res": res, "lends": sorted(lends), "rholds": sorted(rholds),
                "effects": sorted(self.s_effects), "stores": sorted(stores),
                "consumes": sorted(consumes), "elems": sorted(self.s_elems),
                "invokes": sorted(self.s_invokes), "cloargs": sorted(self.s_cloargs),
                "detaches": sorted(self.s_detaches),
                "regions": sorted(self.s_regions), "selfholds": sorted(self.s_selfholds),
                "rclos": sorted(rclos), "sclos": sorted(sclos), "calllends": sorted(calllends),
                "gone": sorted(left_gone), "mixed": [1] if mixed else []}


def initial_summary(prog, fn):
    T = Types(prog)
    return {"modes": list(fn.modes), "res": "none" if fn.ret is None or T.is_scalar(fn.ret) else "own",
            "lends": [], "rholds": [], "effects": [], "stores": [],
            "consumes": [k for k, m in enumerate(fn.modes) if m == "sink"], "elems": [], "invokes": [],
            "cloargs": [], "regions": [], "selfholds": [], "rclos": [], "sclos": [], "detaches": []}


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
    T = Types(prog)
    trusted = getattr(prog, "trusted", ())
    for name, fn in prog.fns.items():
        if name in trusted:
            continue
        fc = FnCheck(prog, fn, summ, final=True)
        sm = fc.check()
        errors += fc.errors
        lent = {k for (k, _, _) in sm["lends"]} & set(sm["consumes"])
        kept = {k for k in sm.get("calllends", ()) if k in sm["consumes"] and fn.modes[k] != "sink"}
        if kept:
            # what a callee lent out of a parameter this function keeps on
            # another path: the parameter is released there, and no copy of
            # the lend was asked for (MEMORY.md §7.6)
            errors.append((name, fn.line, "hands back what a call lends out of a parameter it takes over on another path"))
        elif lent and fn.ret is not None and not T.copyable(fn.ret):
            # the caller cannot both keep an argument the result borrows
            # and have handed it over
            errors.append((name, fn.line, "hands back what it may lend out of a parameter it takes over on another path"))
        if (name.endswith("_clone") or name.endswith("_share")) and sm["res"] == "lent":
            # a handle's copy hook makes a value of its own (§7.6)
            errors.append((name, fn.line, "a copy hook hands its argument back, whole or in part"))
        if getattr(fn, "is_closure", False) and fn.ret is not None and not T.copyable(fn.ret):
            ncap = getattr(fn, "ncap", 0)
            if any(k < ncap and kind == "handle" for (k, _, kind) in sm["lends"]):
                # a closure's result is its caller's own: what it lends out
                # of a capture has to be copied, and this cannot be
                # (MEMORY.md §7.5)
                errors.append((name, fn.line, "a closure hands back, out of what it captured, a value it cannot copy"))
        # (what an argument or a capture holds, handed on by value, is a
        # view only where its type has room for one)
        real = [x for x in sm["stores"]
                if not (x[4] == "held" and x[2] < len(fn.params)
                        and not T.view_capable(fn.vars[fn.params[x[2]]].ty))]
        if getattr(fn, "is_closure", False) and real:
            # a closure's type does not say what running it stores, so
            # nothing where it runs would follow a view it leaves in a
            # capture or in an argument (MEMORY.md §2.11)
            errors.append((name, fn.line, "a closure leaves a capture or an argument holding a view"))
    return errors, summ


def tuple_ify(x):
    if isinstance(x, (list, tuple)):
        return tuple(tuple_ify(i) for i in x)
    return x


def merge_summary(a, b):
    """Summaries only grow, so the fixpoint terminates."""
    order = {"none": 0, "own": 1, "lent": 2}
    out = {"modes": a["modes"], "res": a["res"] if order[a["res"]] >= order[b["res"]] else b["res"]}
    for key in ("lends", "rholds", "effects", "stores", "consumes", "elems", "invokes", "cloargs", "regions", "selfholds", "rclos", "sclos", "calllends", "detaches", "gone", "mixed"):
        out[key] = sorted(set(map(tuple_ify, a.get(key, ()))) | set(map(tuple_ify, b.get(key, ()))), key=repr)
    return out
