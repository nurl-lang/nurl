# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Declared summaries of the standard-library and runtime functions the probes
call.  These are the trust boundary: stdlib bodies are `unsafe` code, so their
summary is declared, never inferred (the design's rule for `unsafe` / `raw` /
FFI functions).

A summary, in the vocabulary of formal/A2's `Fn` plus place paths:

  modes     parameter conventions: 'in', 'inout', 'sink'
  res       'own'    the result is a fresh owned value
            'lent'   the result borrows (see lends)
            'none'   a scalar, or a value holding nothing
  lends     [(k, path, kind)]  the result is a handle ('handle') of, or a
            view ('view') into, place(arg k)+path.  path '*' = an element.
  rholds    [(dpath, k, path, kind)]  the result HOLDS, at its own path
            dpath, a loan on place(arg k)+path (a container of views built
            from arg k); kind 'held' = what arg k holds at path
  effects   [(k, path, eff)]   what the call may do to place(arg k)+path:
            'realloc' (its buffer may move), 'drop' (its elements may be
            dropped), 'replace' (its value may be replaced / freed)
  stores    [(j, dpath, k, path, kind)]  after the call arg j holds at its
            path dpath: kind 'value' = arg k's value itself (moved if owned,
            else its loans); 'held' = what arg k holds at path; any other
            kind = a new loan on place(arg k)+path
  consumes  [k]  arg k is moved into the callee
  elems     [k]  the call reads the elements of arg k (a view held in them
            must still be valid)
"""

E = ("*",)


def S(modes, res="none", lends=(), rholds=(), effects=(), stores=(),
      consumes=(), elems=(), detaches=(), invokes=(), cloargs=(), shares=()):
    return {"modes": list(modes), "res": res, "lends": list(lends),
            "rholds": list(rholds), "effects": list(effects),
            "stores": list(stores), "consumes": list(consumes),
            "elems": list(elems), "detaches": list(detaches),
            # the closure arguments it runs, and what it hands them:
            # (closure argument, its parameter, the argument that is, path)
            "invokes": list(invokes), "cloargs": list(cloargs),
            # the arguments several threads may reach at once
            "shares": list(shares)}


PRIMS = {
    # ---- runtime / builtins -------------------------------------------
    "nurl_println": S(["in"]),
    "nurl_print": S(["in"]),
    "nurl_println_int": S(["in"]),
    "nurl_print_int": S(["in"]),
    "puts": S(["in"]),
    "nurl_str_int": S(["in"], res="own"),
    "nurl_str_len": S(["in"]),
    "nurl_str_cat": S(["in", "in"], res="own"),
    "nurl_str_cat3": S(["in"] * 3, res="own"),
    "nurl_str_cat4": S(["in"] * 4, res="own"),
    "nurl_str_slice": S(["in", "in", "in"], res="own"),
    "nurl_str_get": S(["in", "in"]),
    "nurl_str_find": S(["in", "in"]),
    "nurl_str_eq": S(["in", "in"]),
    # mem_dup: a deep copy that owns everything it holds - except views it
    # holds, which it copies (MEMORY.md §2.13): the copy holds the source's
    # loans.
    "mem_dup": S(["in"], res="own", rholds=[((), 0, (), "held")], elems=[0]),
    # ---- String ---------------------------------------------------------
    "string_from": S(["in"], res="own"),
    "string_new": S([], res="own"),
    "string_with_cap": S(["in"], res="own"),
    "string_clone": S(["in"], res="own"),
    "string_concat": S(["in", "in"], res="own"),
    "string_substr": S(["in", "in", "in"], res="own"),
    "string_data": S(["in"], res="lent", lends=[(0, (), "view")]),
    "string_len": S(["in"]),
    "string_push_str": S(["in", "in"], effects=[(0, (), "realloc")]),
    "string_push_int": S(["in", "in"], effects=[(0, (), "realloc")]),
    "string_push_char": S(["in", "in"], effects=[(0, (), "realloc")]),
    "string_clear": S(["in"], effects=[(0, (), "drop")]),
    "string_free": S(["sink"], consumes=[0]),
    "string_adopt": S(["sink"], res="own", consumes=[0]),
    # ---- Vec ------------------------------------------------------------
    "vec_new": S([], res="own"),
    "vec_with_cap": S(["in"], res="own"),
    "vec_zeroed": S(["in"], res="own"),
    "vec_len": S(["in"]),
    "vec_is_empty": S(["in"]),
    "vec_push": S(["in", "in"], effects=[(0, (), "realloc")],
                  stores=[(0, E, 1, (), "value")]),
    "vec_at": S(["in", "in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "vec_get": S(["in", "in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "vec_clear": S(["in"], effects=[(0, (), "drop")]),
    "vec_truncate": S(["in", "in"], effects=[(0, (), "drop")]),
    # (an option of the element: what the element held, its payload holds)
    "vec_pop": S(["in"], res="own", effects=[(0, (), "drop")], elems=[0],
                 rholds=[(("#T0",), 0, E, "held")]),
    "vec_reserve": S(["in", "in"], effects=[(0, (), "realloc")]),
    "vec_free": S(["sink"], consumes=[0]),
    "vec_clone": S(["in"], res="own", rholds=[((), 0, (), "held")], elems=[0]),
    "vec_put": S(["in", "in", "in"], effects=[(0, E, "replace")],
                 stores=[(0, E, 2, (), "value")]),
    "vec_set": S(["in", "in", "in"], effects=[(0, E, "replace")],
                 stores=[(0, E, 2, (), "value")]),
    "vec_insert": S(["in", "in", "in"], effects=[(0, (), "realloc")],
                    stores=[(0, E, 2, (), "value")]),
    # (the elements change slots and none is released: a handle of one, a
    # view of its buffer stay good; only a loop walking the slots is upset)
    "vec_swap": S(["in", "in", "in"], effects=[(0, E, "permute")]),
    "vec_reverse": S(["in"], effects=[(0, E, "permute")]),
    "vec_extend": S(["in", "in"], effects=[(0, (), "realloc")],
                    stores=[((0, (), 1, (), "held"))], elems=[1]),
    "vec_extend_range": S(["in", "in", "in", "in"], effects=[(0, (), "realloc")],
                          stores=[(0, (), 1, (), "held")], elems=[1]),
    "vec_shrink_to_fit": S(["in"], effects=[(0, (), "realloc")]),
    "vec_remove": S(["in", "in"], res="own", effects=[(0, (), "drop")], elems=[0],
                    rholds=[(("#T0",), 0, E, "held")]),
    "vec_data": None,  # raw pointer: unsafe only
    # ---- Slice ----------------------------------------------------------
    "slice_from_vec": S(["in"], res="lent", lends=[(0, (), "view")]),
    "slice_at": S(["in", "in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "slice_get": S(["in", "in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "slice_len": S(["in"]),
    "slice_sub": S(["in", "in", "in"], res="lent", lends=[(0, (), "view")]),
    "slice_window": S(["in", "in", "in"], res="lent", lends=[(0, (), "view")]),
    "slice_to_vec": S(["in"], res="own", rholds=[((), 0, (), "held")], elems=[0]),
    "slice_put": S(["in", "in", "in"], effects=[(0, E, "replace")],
                   stores=[(0, E, 2, (), "value")]),
    "slice_empty": S([], res="none"),
    # ---- Box --------------------------------------------------------------
    "box_new": S(["in"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    "box_get": S(["in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "box_set": S(["in", "in"], effects=[(0, E, "replace")],
                 stores=[(0, E, 1, (), "value")]),
    "box_free": S(["sink"], consumes=[0]),
    # ---- Rc / Arc / Shared: a counted block every copy of the handle shares --
    "rc_new": S(["in"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    "rc_get": S(["in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "rc_set": S(["in", "in"], effects=[(0, E, "replace")], stores=[(0, E, 1, (), "value")]),
    "rc_take": S(["in"], res="own", effects=[(0, E, "replace")], rholds=[((), 0, E, "held")], elems=[0]),
    "rc_clone": S(["in"], res="own", rholds=[((), 0, (), "held")]),
    "rc_free": S(["sink"], consumes=[0]),
    "arc_new": S(["in"], res="own", rholds=[(E, 0, (), "held")], consumes=[0], shares=[0]),
    "arc_get": S(["in"], res="lent", lends=[(0, E, "handle")], elems=[0]),
    "arc_clone": S(["in"], res="own", rholds=[((), 0, (), "held")]),
    "shared_new": S(["in"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    "shared_clone": S(["in"], res="own", rholds=[((), 0, (), "held")]),
    # ---- trait objects: the box owns the value -------------------------------
    "dyn": S(["in"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    # ---- threads, channels, panics -------------------------------------------
    # a closure a thread runs takes what it captured with it (§2.1)
    "thread_spawn": S(["in"], res="own", detaches=[0]),
    "thread_spawn_owned": S(["in"], res="own", detaches=[0]),
    "spawn": S(["in"], res="own", detaches=[0]),
    "thread_join": S(["in"]),
    "recover": S(["in"], res="own", invokes=[0]),
    "chan_new": S([], res="own"),
    "chan_send": S(["in", "in"], stores=[(0, E, 1, (), "value")]),
    "chan_recv": S(["in"], res="own", rholds=[(("#T0",), 0, E, "held")]),
    "chan_close": S(["in"]),
    # ---- HashMap ---------------------------------------------------------------
    "map_new": S([], res="own"),
    # (the key's old value leaves the map with the result: what was lent
    # out of it is lent out of nothing the map holds)
    "map_set": S(["in"] * 5, res="own", effects=[(0, (), "realloc"), (0, E, "replace")],
                 stores=[(0, E, 1, (), "value"), (0, E, 2, (), "value")],
                 rholds=[(("#T0",), 0, E, "held")]),
    "map_get": S(["in"] * 4, res="lent", lends=[(0, E, "handle")], elems=[0]),
    "map_len": S(["in"]),
    "chan_try_recv": S(["in"], res="own", rholds=[(("#T0",), 0, E, "held")]),
    "spawn_joinable": S(["in"], res="own", detaches=[0]),
    "spawn_owned": S(["in"], res="own", detaches=[0]),
    "atomic_new": S(["in"], res="own"),
    "atomic_add": S(["in", "in"]),
    "atomic_get": S(["in"]),
    "atomic_set": S(["in", "in"]),
    "arc_strong": S(["in"]),
    "rc_strong": S(["in"]),
    "locked_new": S(["sink"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    "rw_new": S(["sink"], res="own", rholds=[(E, 0, (), "held")], consumes=[0]),
    "hash_string": S(["in"]),
    "slice_byte": S(["in", "in"]),
    "nurl_fiber_current": S([]),
    # (the closure is run on each element, lent)
    "vec_each": S(["in", "in"], elems=[0], invokes=[1], cloargs=[(1, 0, 0, E)]),
    # ---- more of the runtime ---------------------------------------------------
    "nurl_panic": S(["in"]),
    "nurl_exit": S(["in"]),
    "strlen": S(["in"]),
    "nurl_eprint": S(["in"]),
    "nurl_eprintln": S(["in"]),
    "nurl_eprintln_int": S(["in"]),
    "nurl_eprint_int": S(["in"]),
    "vec_push_word_u8": S(["in"] * 4, effects=[(0, (), "realloc")]),
    # ---- Option -----------------------------------------------------------
    "opt_unwrap": S(["in"], res="lent", lends=[(0, ("#T0",), "handle")]),
}
