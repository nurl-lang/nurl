### Fixed

- **A `;` defer in a `~` loop's body that reads the loop's element is
  checked at the function's exit** (Agora #672). The defer runs once, when
  the function returns, and reads the element of the last round that
  reached it; with the container cleared, given a new value or handed
  away after the loop, it read freed memory. The element now lives, as a
  borrow of its container, from the loop's end to the exit — as
  `: String e ( vec_at [String] v 0 )` does — also inside another loop,
  so such a program is refused as that binding's is, with a note saying
  the defer runs when the function returns. A defer that reads the
  element of a container nothing changes after the loop is accepted as
  before.
