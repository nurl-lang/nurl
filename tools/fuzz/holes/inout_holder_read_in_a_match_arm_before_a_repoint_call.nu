// inout_holder_read_in_a_match_arm_before_a_repoint_call: `( g ?? … { T r → r
// F → . w v } ( reset w ) )`. The `??` arm reads the holder's old view
// before reset runs, and the walk sees that read after reset's assign row.
// Not credited: still refused, as on main (agora #386).
// map: §3.3d | A2 | rejected | - | a holder read in a `??` arm before a repointing call in the same statement: not credited (agora #386).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ reset inout W w → i { = w @ W { `fresh` } ^ 0 }

@ g s x i k → i { ( nurl_println x ) ^ k }

@ main → i { : ~ W w @ W { `start` } : ( Vec s ) e ( vec_new [s] ) ? T { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) = w @ W { ( string_data b ) } } {} ( nurl_println_int ( g ?? ( vec_get [s] e 0 ) { T r → r F → . w v } ( reset w ) ) ) ^ 0 }
