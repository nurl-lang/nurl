import B.Vec
import B.String
import B.Rc

/-! Phase B: the standard library's `unsafe` base meets the semantic types
the rules give it. B1: `Vec`'s raw core (`B/Vec.lean`). B2: `String`'s NUL
discipline over it (`B/String.lean`). B3: `rcbox`, the counted block behind
library handles and `Shared` (`B/Rc.lean`). -/
