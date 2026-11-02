### Fixed

- **A defer body's own bindings live until the defer chain has run**
  (Agora #405; test defer_body_own_locals). Take a `;` defer that declares
  a Vec or a String of its own, with no later defer to snapshot it:
  `; { : ( Vec i ) g ( vec_new [i] ) … }`. `g` was dropped at every `^` in
  the main flow, before the body had run, from a slot that held nothing
  (segmentation fault). It was never dropped after the body had run (a
  leak). It is now snapshotted after the body, as what came before the
  `;` is, and reclaimed after the chain, so child defers armed in the body
  still read it. One case is still open (open/t405.md): a defer in an arm
  that is not taken, which binds a value of its own.
