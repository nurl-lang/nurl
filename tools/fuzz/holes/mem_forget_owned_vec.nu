// mem_forget_owned_vec: ( mem_forget v ) is accepted in safe code, and the owned Vec is never released.
// Closed: the ownership primitives (mem_forget, mem_take, mem_put_back) are `unsafe`-only (bck_check_raw_call).
// §3.3d makes mem_forget `unsafe`-only and the compiler's raw-primitive list names it, but the special
// form is dispatched before that check runs, so any safe function may give up an owned value unreleased.
// LSan: detected memory leaks — the Vec's control block (24 bytes) and its element buffer (32 bytes).
// map: §3 | B | rejected | h155 | mem_forget of owned Vec accepted in safe code (leak)
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( mem_forget v )
    ( nurl_println `ran` )
    ^ 0
}
