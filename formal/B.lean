import B.Vec
import B.String
import B.Rc
import B.Map
import B.Arc
import B.Channel
import B.Cycle

/-! Phase B: the standard library's `unsafe` base meets the semantic types
the rules give it. B1: `Vec`'s raw core (`B/Vec.lean`). B2: `String`'s NUL
discipline over it (`B/String.lean`). B3: `rcbox`, the counted block behind
library handles and `Shared` (`B/Rc.lean`). B4: `HashMap`'s slot code
(`B/Map.lean`). B5: `Arc` and `ArcWeak` (`B/Arc.lean`). B6: `Channel`'s queue
(`B/Channel.lean`). B7: the `Rc` cycle collector's criterion (`B/Cycle.lean`). -/
