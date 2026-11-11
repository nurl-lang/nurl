### Fixed

- **An owned slice that a loop body's `;` defer keeps is released every
  round** (Agora #676, `compiler/nurlc.nu`). `: [i xs [i | …]` above a
  `;` inside a loop left every round's buffer but the last unreleased
  (and the elements of a slice of Strings with it), though a String or a
  Vec beside it was parked and released since Agora #655. A slice is
  listed by its storage, not as a value with a destructor, so the parking
  wrote nothing for it; it now parks the slice under its "left to the
  cleanup" flag and releases its elements and its buffer after the defer
  chain.
