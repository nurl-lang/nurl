### Fixed

- **A slice binding owns its buffer by its own flag where the owner can
  differ from run to run** (Agora #540). A function that hands back its
  own slice on one path and a slice parameter on another was taken to
  lend on every run, so the slice it handed back was never freed. It now
  answers per call, the way a handle result does (`@.__nurl_retdyn`), and
  the caller's binding owns the slice by that answer. A slice from a
  function compiled further down the file leaked the same way. It now
  takes that function's module-end answer.
- **`= d p` no longer frees the caller's slice.** A mutable slice that
  owned its buffer stayed owned after it was given a parameter, so its
  drop freed the caller's buffer (heap use after free). Now `d`'s old
  buffer is freed, unless `p` points into it, and `d` no longer owns
  anything.
- **`= d a` from a longer-lived owned slice keeps `a` the owner.** Before,
  the buffer moved to `d` while `a` could still be read, and the next
  `= d [ … ]` freed it under that read, also in a loop and under a panic's
  unwind. Now `d` views `a`. When `a` comes from a scope inside `d`'s,
  `d` inherits the buffer where `a` would release it, if `d` still holds
  that very buffer.

Optimized code is unchanged for slices whose owner is known statically.
The compiler's own self-compile stays within noise (+0.1–0.2 %
instructions, the size of a split-link shift).
