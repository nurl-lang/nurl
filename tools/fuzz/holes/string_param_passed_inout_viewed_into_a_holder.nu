// string_param_passed_inout_viewed_into_a_holder: agora #337 — the String is passed `inout` itself: `repoint w s` leaves `w` viewing it, and `w` is read after it ends.
// Closed: an owner passed `inout` gets its `bK` row too, as A2's outHolds takes an inout argument as a source like any other (agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String passed inout, viewed into the holder beside it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w inout String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : ~ String s ( string_from `a string freed at the end of its block` )
        ( repoint w s )
    }
    ( nurl_println . w v )
    ^ 0
}
