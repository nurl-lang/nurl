// inout_holder_viewing_a_callee_local_moved_into_the_callers_field_returns: a callee views its local String into an inout holder, moves the String into the caller's inout field and returns; the caller replaces that field and reads the holder (PO probe r39).
// Closed: the holder's views move with the local into the field, so the caller is refused the replace or the read (agora #381). Refused on main 9e8d4a88.
// main d85806eb / 8a2afbc: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #381: an inout holder viewing a callee local moved into the caller's inout field, with ^
$ `stdlib/core/string.nu`

: W { s v }
: K { String keep }

@ fill inout W w inout K h → i {
    : String b ( string_from `the callee's local string, moved into the caller's field` )
    = w @ W { ( string_data b ) }
    = . h keep b
    ^ 0
}

@ main → i {
    : ~ W w @ W { `literal` }
    : ~ K h @ K { ( string_from `the caller's first keep, long enough for heap` ) }
    : i _r ( fill w h )
    = . h keep ( string_from `the caller's second keep, long enough for heap` )
    ( nurl_println . w v )
    ^ 0
}
