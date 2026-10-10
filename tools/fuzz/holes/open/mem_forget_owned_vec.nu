// OPEN in 0.72.0 — ( mem_forget v ) is accepted in safe code, and the owned Vec is never released.
// §3.3d makes mem_forget `unsafe`-only and the compiler's raw-primitive list names it, but the special
// form is dispatched before that check runs, so any safe function may give up an owned value unreleased.
// LSan: detected memory leaks — the Vec's control block (24 bytes) and its element buffer (32 bytes).
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( mem_forget v )
    ( nurl_println `ran` )
    ^ 0
}
