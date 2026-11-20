### Fixed

- **A `:` join whose arm reads a field of an inner struct can no longer outlive that struct** (AGORA-941). `: t ? c . p s ( mk )`, followed by `= outer t` and a read of `outer` after the block, read a freed field. It is refused now. Read the value inside the block, or hand it on with `= outer ? c . p s ( mk )`, which copies the field.
