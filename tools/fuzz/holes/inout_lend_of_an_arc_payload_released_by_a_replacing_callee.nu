// inout_lend_of_an_arc_payload_released_by_a_replacing_callee: as h367, the binding what arc_get lends (`: ~ String s ( arc_get [String] a )`): the callee released the Arc's payload — on another thread holding a clone, a use-after-free under its reader.
// Closed: as h367 — a call's lend is a borrow of its argument (bck_inout_borrow_check, agora #135).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | h369 | as h367, the binding what arc_get lends: the callee released the Arc's payload
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

@ rename inout String s → v { = s ( string_from `a new name, long enough for a heap buffer` ) }

@ main → i {
    : ( Arc String ) a ( arc_new [String] ( string_from `the shared name, long enough for a heap buffer` ) )
    : ~ String s ( arc_get [String] a )
    ( rename s )
    ( nurl_println ( string_data ( arc_get [String] a ) ) )
    ^ 0
}
