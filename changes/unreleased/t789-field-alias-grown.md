### Fixed

- **An alias of a struct field, handed to a callee that grows one of its elements, now ends views taken through the original path** (AGORA-789). Take `: I ii . ww inner`, a slice of `( vec_at [( Vec u )] . . ww inner rows 0 )`, then `( top ii )`. The slice outlived the growth and read freed memory. It is refused now. A view of a sibling field (`. . ww other rows`) is still accepted.
