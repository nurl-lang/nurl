### Fixed

- **The last AGORA-842 shapes are refused** (AGORA-842 part 2):
  - a callee growing an element of its option parameter's payload inline, `?? p { T q → ( vec_push ( vec_at q 0 ) … ) }`, including through `rc_get` or `box_get`;
  - an option and a slice of its payload handed to one call that grows the payload;
  - a view of an enum payload's element kept past the enum being moved or sunk.

  Each read freed memory. The same programs that only read, or that read the view first, are still accepted.
