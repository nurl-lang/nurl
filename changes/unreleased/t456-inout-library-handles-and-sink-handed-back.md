### Fixed

- **An `inout` Box, HashMap, Rc or Arc given a lend of another value copies
  it in** (Agora #456; probes inout_box_given_*, inout_hashmap_*,
  inout_rc_*, inout_arc_*). `@ put inout ( Box String ) o ( Box String )
  other → v { = o ( idbox other ) }` stored `other`'s Box as it was: the
  caller's binding and `other`'s owner then shared one value and both
  released it. A library handle that is one pointer is now told apart by
  that pointer, as a String is by its buffer: a lend of another value is
  copied in (an Rc or Arc as a new share) and the old value released; the
  binding's own value, or another share of the same Rc, stays.
- **A function handing back its `sink` argument on some runs says so per
  run** (Agora #456; probes inout_string_given_a_sink_argument_*).
  `@ cpick String a sink String b i k → String` returning `a` on one path
  and `b` on another answered "lent" on both, so `= o ( cpick o ( mk ) 1 )`
  over an `inout` never released `o`'s old value. A `sink` parameter is the
  function's own, and its handed-back value now counts as the caller's.
