### Changed

- **A second name for a local slice is that slice** (Agora #664). `: [i c a` out of an owned slice moves it, so `( eat c )` with eat a `sink [i` parameter is refused, as `( eat a )` already is ("passing a compiler-auto-dropped value to a 'sink' parameter is not yet supported"). Before, c was a borrow, and the sink was handed a value nobody accounted for.
