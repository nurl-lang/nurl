// H869: agora #196 — an `inout` assignment of a value made from a parameter's lend: nothing of this frame's (inout_assign_param_derived).
// Closed: An `inout` parameter assigned a call's value — or a block's or a try's ending in one — that may lend out of this function's locals gets a copy where it lent, and the caller's old value is dropped there; a value that cannot be copied is refused (agora #196).
// main: accepted and ran clean (kept as a guard).
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ fill inout String io W p → v { = io ( string_from ( string_data ( gets p ) ) ) }

@ main → i {
    : ~ String t ( string_from `start` )
    : W p ( mkw )
    ( fill t p )
    ( nurl_println_int + ( string_len t ) ( string_len . p s ) )
    ^ 0
}
