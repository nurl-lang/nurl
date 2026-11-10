// inout_holder_read_before_a_repoint_call_in_the_same_statement: `( g . w v
// ( reset w ) )` reads the holder's old view, of a String that ended in an
// inner block, before reset runs. The walk checks a statement's reads after
// the rows its calls record, so crediting reset's repoint let that read
// pass (formal's review of #1709: a use-after-free). The credit applies only
// where the call's own argument is the statement's one read of the holder so
// far: still refused, as on main (agora #386).
// map: §3.3d | A2 | rejected | - | a holder read before a repointing call in the same statement: the repoint is not credited there (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W { `fresh` } ^ 0 }

@ g s x i k → i { ( nurl_println x ) ^ k }

@ g2 i k s x → i { ( nurl_println x ) ^ k }

@ main → i { : ~ W w @ W { `start` } ? T { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) = w @ W { ( string_data b ) } } {} ( nurl_println_int ( g . w v ( reset w ) ) ) ^ 0 }
