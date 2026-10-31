// inout_assign_local_field: agora #196 — `= io . w s`, a field of the local struct `w` assigned to an `inout` parameter (inout_assign_local_field).
// Closed: A field read of a value this frame owns, assigned to an `inout` parameter, is copied and the caller's old value dropped; one that cannot be copied is refused (agora #196).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h870 | agora #196: `= io . w s`, a field of the local struct `w` assigned to an `inout` parameter
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ fill inout String io → v {
    : W w ( mkw )
    = io . w s
}

@ main → i {
    : ~ String t ( string_from `start` )
    ( fill t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
