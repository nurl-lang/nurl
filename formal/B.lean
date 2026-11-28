module

public import B.Vec
public import B.String
public import B.Rc
public import B.Map
public import B.Arc
public import B.Channel
public import B.Cycle
public import B.Size
public import B.StdRc

@[expose] public section

/-! Phase B: the standard library's `unsafe` base meets the semantic types
the rules give it. B1: `Vec`'s raw core (`B/Vec.lean`). B2: `String`'s NUL
discipline over it (`B/String.lean`). B3: `rcbox`, the counted block behind
library handles and `Shared` (`B/Rc.lean`). B4: `HashMap`'s slot code
(`B/Map.lean`). B5: `Arc` and `ArcWeak` (`B/Arc.lean`). B6: `Channel`'s queue
(`B/Channel.lean`). B7: the `Rc` cycle collector's criterion (`B/Cycle.lean`). B8: allocation sizes never wrap
(`B/Size.lean`). B9: `std/rc.nu`'s `Rc`, `Weak` and the check-out (`B/StdRc.lean`). -/
