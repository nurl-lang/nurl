// inout_holder_read_in_a_block_tail_before_a_repoint_call: `( g { . w v }
// ( reset w ) )`. The block's tail reads the holder's old view, of a String
// that ended in an inner block, where the block ends, which is after the
// assign row a credited reset records (formal's review of #1709: a
// use-after-free). The credit needs the holder argument to be the one read
// its top-level statement has made so far: still refused, as on main
// (agora #386).
// map: §3.3d | A2 | rejected | - | a holder read in a value block's tail before a repointing call in the same statement: not credited (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W { `fresh` } ^ 0 }

@ g s x i k → i { ( nurl_println x ) ^ k }

@ ids s x → s { ^ x }

@ main → i { : ~ W w @ W { `start` } : b c T ? T { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) = w @ W { ( string_data b ) } } {} ( nurl_println_int ( g { . w v } ( reset w ) ) ) ^ 0 }
