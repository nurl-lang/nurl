// H851: agora #191 — an arm's call lending a binding of the enclosing code: not copied, nothing of the arm's to drop (arm_call_outer_local).
// Closed: An arm whose value is a call's lend out of a binding the arm owns itself copies it on those paths (mem_arm_take_call), so the arm hands over a value of its own and its locals are dropped at its exit even when the join's value is consumed (agora #191).
// main: accepted and ran clean (kept as a guard: no copy).
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : b c T
    : W w ( mkw )
    : String r ? c ( gets w ) ( string_from `fresh` )
    ( nurl_println_int ( string_len r ) )
    ^ 0
}
