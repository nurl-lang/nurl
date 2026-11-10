// inout_holder_read_after_a_repoint_call_in_the_same_statement_runs_clean:
// `( g2 ( reset w ) . w v )` reads the holder only after reset gave it a
// literal, so the String it viewed before, which ended in an inner block, is
// not read. The repoint is credited: the holder's first read in the
// statement is reset's own argument (agora #386).
// map: §3.3d | A2 | runs-clean | - | a holder read after a repointing call in the same statement: credited, runs clean (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W { `fresh` } ^ 0 }

@ g s x i k → i { ( nurl_println x ) ^ k }

@ g2 i k s x → i { ( nurl_println x ) ^ k }

@ main → i { : ~ W w @ W { `start` } ? T { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) = w @ W { ( string_data b ) } } {} ( nurl_println_int ( g2 ( reset w ) . w v ) ) ^ 0 }
