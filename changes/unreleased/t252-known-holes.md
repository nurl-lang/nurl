### Known issues

- **Three soundness holes are open, each with a fix in progress**:
  agora #242 (a join or value block bound by `:` and handed on by name),
  #247 (a `thread_spawn` closure that consumes one capture releases
  another) and #252 (a `% Drop` value holding a view, moved on only one
  branch of a `?`). `docs/LIMITATIONS.md` gives each one's shape and how
  to stay clear of it. A release does not say "no hole is known open"
  while one is.
