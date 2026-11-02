### Fixed

- **A buffer moved through more kinds of handle copy ends the owner's
  views** (Agora #440; probes view_kept_past_a_push_through_a_copy_*,
  field_view_kept_past_a_push_through_a_copy_a_callee_lends). Three kinds
  of copy were missed:
  - a copy made by a call that may hand back either of two arguments (`:
    ~ String o ( pick x other 1 )`);
  - a copy made by `=` over an owned binding (`= c ( id b )`);
  - a field a callee hands back (`: String c ( name_of hs )`).

  A view of the original survived the copy growing (heap-use-after-free).
  A String or Vec borrowed from bindings of its own type now counts as a
  copy of their handle. A field lent by a callee, when its buffer moves,
  ends the views of the struct and its fields.
