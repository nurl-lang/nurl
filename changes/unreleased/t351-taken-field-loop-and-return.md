### Fixed

- **A field a `sink` took stays taken around a loop, and handing it back
  is a read** (Agora #351). A take inside a loop was forgotten at the next
  round: the loop reset the field path, which had no state before the
  take, as a binding the body declares. The next round took or pushed to
  the null handle. The path now stays taken, or maybe taken, at the loop's
  head and after it (by its end or a `break`) when its struct was bound
  before the loop. `^ . h buf`, `^ @ Holder { . h buf }` and
  `= h @ Holder { . h buf }` after the take are refused as a use of the
  moved field: the `ret` row named only `h`, and a literal's field read
  of a path recorded nothing. A loop's report says an earlier round took
  the field.
