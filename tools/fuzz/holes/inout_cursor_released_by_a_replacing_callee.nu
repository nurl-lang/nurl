// inout_cursor_released_by_a_replacing_callee: an `inout` argument whose binding was a cursor over another binding (`: ~ ( Vec i ) cur root`), handed to a callee that gives its parameter a new value: the callee released the old value — root's buffer — and stored the new one in cur's slot; root read freed memory and dropped it again. The rule for this shape (h295) covered only a `: ~` copy of a parameter.
// Closed: the walk refuses an argument in a borrow state (a cursor, a parameter's copy, a field read, a lend; on any path) handed to a parameter its callee may replace or replace a field of (bck_inout_borrow_check, agora #135).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | h367 | a : ~ cursor over another binding handed inout to a callee that gives the parameter a new value: the callee released the owner's buffer; an argument in a borrow state may not go to a parameter its callee may replace
$ `stdlib/core/vec.nu`

@ reset inout ( Vec i ) v → v { = v ( vec_new [i] ) }

@ main → i {
    : ( Vec i ) root ( vec_new [i] )
    ( vec_push [i] root 5 )
    : ~ ( Vec i ) cur root
    ( reset cur )
    ^ ( vec_len [i] root )
}
