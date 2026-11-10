### Fixed

- **A field of an inner block's borrow, given to an outer binding, stays tied to the container** (Agora #533). `{ : E x ( vec_at [E] top 0 )  = w . x kids }`, then `( vec_clear [E] top )`: `w` was taken to own the field, as it would from an owned struct, so the clear left it reading freed memory (a heap-use-after-free). It now borrows from `top` past the block, and the read after the clear is refused, as the same lines without the block are. A String field, an element of an element and a loop body are handled the same way. An owned struct's field still moves out to the binding.
