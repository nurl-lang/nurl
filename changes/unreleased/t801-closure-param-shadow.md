### Fixed

- **A closure's parameter named like the function's no longer counts as the
  function's** (Agora #801). A literal `\ ( Vec ( Vec u ) ) vv → v { … }`
  inside `@ top ( Vec ( Vec u ) ) vv …` that grew its own `vv`'s element
  was taken to grow `top`'s `vv` too, so a caller's slice of what it
  passed `top` was refused after the call. A closure that captures the
  function's parameter is still refused, as before.
