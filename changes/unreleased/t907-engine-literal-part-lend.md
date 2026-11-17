### Fixed

- **A value assigned back a part of itself is copied in whichever order the functions are written** (AGORA-907, AGORA-906). Take `= o ( tail o )`, where `tail` hands back `@ ?N { T ( box_get [N] b ) }` (a node behind `o`'s own `Box`). It still read freed memory when `tail` was defined below its caller. Two related shapes, `= o ( choose o k )` (`o` itself on some runs, the part on others) and `= o ( npick o ( tail o ) k )`, leaked or were refused depending on that order. All of them now run clean in either order: `o` gets its own copy on the runs where the call lent. Only types that can hold a value of their own type are affected; no in-repo code changes.

### Changed

- **The ownership engine (`nurlc --engine`) and tools/ncore follow those copies, and a returned literal that holds a part of a parameter** (AGORA-907). The core IR marks such a literal. Both checkers read the copy-in mark on any binding, not only on a closure capture.
