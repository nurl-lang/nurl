### Fixed

- **A value block whose tail shadows the assigned name** (Agora #562). `= v { : ~ ( Vec i ) v ( vec_new [i] ) … v }`, and the same for a String or a struct, released the new value as if it were the old one, which then leaked, and `v` read freed memory (a heap-use-after-free). The block's own `v` stays visible to the end of the statement, so the assignment had taken it for the target. The assignment now finds its target before the right-hand side is made.
