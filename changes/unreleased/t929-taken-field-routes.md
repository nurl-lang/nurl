### Fixed

- **A field a `sink` took can no longer be reached by more routes** (AGORA-929, part of AGORA-280's rest). Each of these was accepted and ran into the emptied field's null handle, or into freed memory, and is refused now:
  - a path over or under the taken one (`. o a` used with `. . o a buf` taken, or the reverse);
  - the holder handed on whole by `= h2 h`, by `^ @ Outer { h }`, or by a value block `{ h }`;
  - `= . g buf . h buf`;
  - a closure made after the take that pushes to the field, run while the field is empty or handed back on the line it is made on.

  Give the field a value again first, or hand the callee a copy.
