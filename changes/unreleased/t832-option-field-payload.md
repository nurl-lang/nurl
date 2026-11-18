### Fixed

- **A view into the payload of a matched option field now ends when a callee grows that field** (AGORA-832). In `?? . h o { T q → : ( Slice i ) sl ( slice_from_vec [i] q )  ( w . h o ) … }`, `sl` outlived `w` growing the payload. The same happened when a wrapper handed `. h o` on to an `inout` parameter, because the wrapper's summary was empty. Both are refused now. Growing another field of `h` still leaves the view alone.
