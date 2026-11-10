// inout_holder_repointed_after_a_division_that_may_panic: `: i q / 10 n` before
// the literal write panics when n is 0, and the holder keeps its old view
// (formal's review of #1709: a use-after-free under recover). Only a write
// that is the body's first statement is credited: still refused.
// map: §3.3d | A2 | rejected | - | a helper whose repoint follows a division that may panic: the credited write must be the body's first statement (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w i n → i { : i q / 10 n = w @ W { `fresh` } ^ q }

@ main → i { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) : ~ W w @ W { ( string_data b ) } ( reset w 0 ) ( string_free b ) ( nurl_println . w v ) ^ 0 }
