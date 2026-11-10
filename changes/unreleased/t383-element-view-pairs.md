### Fixed

- **A callee that leaves one argument viewing another's elements ties the
  caller's holder to those elements** (Agora #383). `put arena idx key`
  pushing `key` into `arena`, binding `: String e ( vec_at arena n )` and
  pushing `string_data e` into `idx` left the caller's `idx` tied to
  nothing: `vec_clear`, `vec_pop`, `vec_truncate` or `vec_put` on
  `arena`, or the viewed element growing, left `idx` reading freed
  memory. The callee's answer now has an element pair, `h>^k`: the
  holder depends on argument k's elements, as a local view of an element
  does. Pushing more into the arena, which moves only its own buffer,
  stays accepted.
- **An owner handed back whole that views its own storage is accepted**
  (Agora #383). A struct whose index field views the elements of its
  arena field (`^ t`) was refused as "a view of 't'": a move leaves the
  buffers where they are, so the views go with it. A borrow handed back
  (a copy) is still refused.
- **`map_set` replacing a value that owns nothing drops nothing**
  (Agora #383). A wrapper of `map_set` on a `( HashMap s i )` counted as
  dropping its map's contents, so handing a struct that holds such a map
  beside an arena to a helper ended every view of the arena's elements
  (yoloe's tokenizer).
