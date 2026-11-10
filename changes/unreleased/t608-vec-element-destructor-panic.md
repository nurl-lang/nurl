### Fixed

- **A `Vec` element whose destructor panics no longer ends the release of
  the elements after it** (Agora #608). Under `recover`, a `% Drop`
  element that panicked while its `Vec` was dropped left the runtime's
  element loop: the elements after it never ran their destructors, and
  they, the buffer and the `Vec` leaked. `vec_truncate` and `vec_clear`
  lost the rest of their tail the same way, and a `Vec` inside a `Vec`
  lost both. The release is in the panic journal now, as the elements
  still to go: a panic's drain goes on from there, in index order and once
  each, frees the buffer and the `Vec`, and only then jumps to the
  `recover`, which still reports the first panic's message. However many
  of the elements panic, each is caught where the release goes on, so the
  stack is no deeper than for one. A panic that
  left the element loop also left the thread's cycle collector switched
  off for good; it is switched back on where the release ends. Outside a
  `recover` extent, where a panic ends the process, nothing is recorded,
  and a `Vec` whose elements run no code of the program's own when they
  are dropped (a `String`, a `Vec` or a struct of plain data) is released
  by the loop it always was, inside a `recover` extent too.
  This is the run `formal/CLAIM.md`'s drain describes
  (`Step.scopeDPDrain`); its note that the runtime did otherwise is gone.

### Changed

- **`vec_truncate` and `vec_clear` drop their elements through one runtime
  call** (Agora #608), `( mem_drop_range [T] data from to )`, a raw
  ownership primitive beside `mem_take`: no code at all for elements that
  own nothing, one call for the whole tail otherwise (0.3 % fewer
  instructions clearing a `( Vec String )` of sixteen).
