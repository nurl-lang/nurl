### Fixed

- **A bound value block of a parameter's field, handed back, lends that field** (Agora #570). `@ pick H h → ( Vec S ) { : ( Vec S ) j { . h a }  ^ j }` gave the caller a result tied to nothing; clearing it, or clearing `. h a` under a borrow taken through it, read freed memory. A binding of a block whose tail is a field read is now that read, as `: j . h a` is, and the call is refused the same way. A closure parameter cleared through a binding remains open (Agora #570).
