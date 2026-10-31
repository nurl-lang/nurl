### Fixed

- **A `?` / `??` or a value block bound by `:` and then handed on by name
  is no longer a use-after-free or a leak** (Agora #242). The
  probes covered each producer handed on directly (`^ ? c a b`); their
  elaborated twins (`: t ? c a b` then `^ t`) were not covered, and 24 of
  58 faulted. Found by a new oracle: `tools/fuzz/holes/check.sh` now runs
  each probe's elaborated twin too (`tools/fuzz/holes/elab.py`).
  - A `:` binding of a join takes the owner its arm selects on that path,
    as docs/MEMORY.md §2.2 says and `^` already did. It gives the owner
    back where it dies still holding it while the owner lives on, as a
    loop body's binding of an owner made before the loop does. The
    checker accepts exactly what it accepted before.
  - An `inout` parameter assigned a binding that owns its value on some
    paths takes it with its flag. It used to be stored as is while the
    binding still released it.
  - A value block ending in a fresh call, bound by `:`, owns the call's
    result. It used to leak.
  - A `% Drop` value bound from a join over a borrowed parameter and a
    local is handed back with a per-call answer.

  Nine twins remain open: the binding does not inherit what its producer
  lends. They are listed in `tools/fuzz/holes/open/twins.txt`, and the
  elaboration of #222 closes them.
