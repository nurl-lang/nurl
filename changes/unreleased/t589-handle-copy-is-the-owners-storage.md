### Fixed

- **A container and a cursor of it handed to one call are seen as the same
  container** (Agora #589). With `: ~ ( Vec String ) cur t`, `( walk t cur
  )` — `walk` looping over its first parameter while it grows its second —
  moved the buffer under the callee's loop (heap use after free), where
  `( walk t t )` was refused. The same held for a struct and a cursor of
  it, for a callee handed `t` and a closure that grows `cur`, and for a
  closure whose body loops over captured `t` and grows captured `cur`. All
  are refused now; a cursor of another container is unaffected.
