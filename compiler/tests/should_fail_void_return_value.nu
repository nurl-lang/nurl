// A function declared `→ v` (returns nothing) must reject `^ <value>`:
// it would lower to `ret i64 …` out of a void LLVM function (invalid IR
// that historically only clang caught). The cure is a bare `^`.
@ f i x → v { ? > x 0 { ^ 0 } {} ( nurl_print `end\n` ) }

@ main → i { ( f 5 ) ^ 0 }
