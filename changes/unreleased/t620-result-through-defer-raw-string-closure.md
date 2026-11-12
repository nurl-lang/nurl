### Fixed

- **A function's result is kept when a `;` defer body panics after it is
  set, and when it is a raw string or a closure** (Agora #620). Under
  `recover`, three results were in no journal entry while code of the
  program's own could still run before the `ret`: one held in the
  function's result slot through the defer chain (a literal, an option
  over a binding, a raw string), a fresh raw string handed back
  (`^ ( nurl_str_cat … )`) while a local's destructor panicked, and a
  closure handed back — a literal or a call's — whose environment owned
  something. Each is now released once by the unwind: its destructor runs,
  its memory is freed.
