### Fixed

- **Who owns a slice buffer follows the path at run time, not list membership** (Agora #664, #540). These were heap-use-after-free, double frees, or leaks:
  - `: [i c a  : [i d c  ^ d`: a second name for a local slice. An immutable `:` of an owned slice is now a move, as `= dst src` is.
  - `^ ? c a b` over two local slices. The return frees each local only where its buffer is not the one handed back.
  - `^ . q xs`, a slice field of a local struct. The field is now taken.
  - A join of a fresh slice and a borrowed one, bound or assigned (`?` and `??`). The binding owns the buffer by the join's bit.
  - `^ [i | ( sum a ) 6]` leaked `a`.
  - `= r xs` over an owned `r` freed the caller's `xs`, and `: ~ [i r xs  = r [i | …]` leaked the literal. A `: ~` slice now has a drop flag from its `:`.
  - A function returning its own slice on one path and a parameter's on another leaked the owned one. It now answers per call, and the caller drops by that answer.
