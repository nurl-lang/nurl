### Fixed

- **A slice taken through a copy of a Vec's handle ends when the Vec grows through its own name** (AGORA-428, the copy shapes). With `: ~ w vs  : sl ( slice_from_vec w )`, a push through `vs` moved the buffer `sl` pointed into, and a later read of `sl` read freed memory. The same held for `( id ( id vs ) )` and for a join of copies. All three are refused now. A view of an element's own String taken through the copy is still accepted.
