### Changed

- **`: String k ( id s )`, then `= s ( … )`, then reading `k` is accepted: `k` takes the old value over** (AGORA-1003). Take a call that hands its argument back whole, `id String p → String { ^ p }`. The generated code already gave `k` the old value at `= s` and never freed it under `k`: it found `k` holding the same buffer, and the program ran clean under ASan. The reference checker and the ownership engine accepted it too. Only the borrow checker refused it, with "'k' borrows from 's', which ended at … — it was given a new value". It now takes `k` as the owner of that value from then on, for a `String` or a `Vec` of the owner's type, in a function or a closure body, on every path that gives `s` a new value. Unchanged:
  - **refused as before:** two or more such bindings linked to `s`, a `: ~ k`, and `= k ( id s )`, which the code does not link to `s` (agora #881);
  - **an `inout` parameter** given a new value still frees its old value outright (agora #886);
  - **every program accepted before** compiles to the same code.
