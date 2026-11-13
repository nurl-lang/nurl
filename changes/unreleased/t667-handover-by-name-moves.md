### Fixed

- **A handover by name out of a binding that may own its value is a move**
  (Agora #667). `= b x`, where `x` owns its value on some paths only
  (`? c ( string_from … ) borrowed`), made `b` a cursor over `x`. For an
  option, the walk took the handover for a copy while the generated code
  moved the drop flag. Either way, a second name could read the value
  after the first freed it. The target now takes `x`'s run-time flag, and
  a read of `x` before it has a new value is refused. A #634 rotation out
  of such a source now compiles and runs clean. The same move is made in
  `unsafe` and trusted code, where the cursor path made the rotation read
  freed memory.
- **A source given a new value after a handover survives a panic**
  (Agora #667). `= t a` forgot `a`'s panic-journal entry, and nothing
  registered it again at `= a …`, so under `recover` a panic leaked `a`'s
  new value. The entry follows `a`'s drop flag and is now kept.
- **An owner given back a lend of itself keeps it** (Agora #667).
  `: x { v }` binds a lend of `v`, and `= v x` released v's value and
  stored the freed buffer back. Such a binding is now checked by its key,
  as a cursor is.
