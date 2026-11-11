### Fixed

- **A HashMap, a Set, a Deque and a BTree go on releasing their entries
  when an entry's destructor panics** (Agora #659). Under `recover`, each
  of these stopped at the first key, value or element whose `% Drop`
  panicked: the entries after it ran no destructor and what they owned
  leaked — and a `deque_clear` that panicked left a deque that had lost
  the rest. An entry now leaves its container before its destructor runs,
  and the release in progress is recorded in the panic journal, as a
  `Vec`'s is: the entries after the panicking one are dropped, once each,
  then the container's buffers, and only then does the panic reach its
  `recover` — the first panic's message, however many destructors panic,
  on a stack no deeper than for one. `map_remove`, and `map_set` /
  `btree_set` replacing an entry, drop the key that goes while the value
  they hand back is still owned by the frame, so a key's destructor that
  panics no longer leaks that value. Containers whose entries run no code
  of the program's own when dropped (plain data, `String`s, `Vec`s of
  them) compile to exactly what they did: the choice is a constant,
  `( mem_drop_runs_code [T] )` (docs/MEMORY.md §7.2). The same protocol is
  there for a container of your own: a restartable release, a record
  whose drop is `( mem_release_rest … )` (stdlib/core/mem.nu).

### Performance

- **A statement `?` on a type predicate compiles only the arm it selects**
  (Agora #659). `? ( mem_cyclic [A] ) { … } { … }` and its siblings
  (`mem_rc_nested`, `mem_resource`, the new `mem_drop_runs_code`) are
  constants of the generic instance being compiled; the arm the constant
  leaves out was generated all the same and left for LLVM to delete, with
  everything it instantiated. In the standard library and in `unsafe`
  functions, where these predicates are written, it is passed over now
  (safe code's `?` is compiled and checked exactly as before): an `Rc` of a payload
  that can form no cycle asks for no collector table (`rc_basic`: 3.4 %
  less IR, 1 % fewer compiler instructions), and a container of plain
  data instantiates nothing of the release a container of destructor
  values needs. The `mem_*` intrinsics are also looked up behind one
  prefix test instead of twenty name comparisons on every call the
  compiler generates.
