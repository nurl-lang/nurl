// field_read_off_a_field_taken_from_a_generic_call_result: agora #474 — the generic form of field_read_off_a_field_taken_from_a_call_result: `. . ( boxit [String] @ ( Pair String ) { … } ) v b` left the taken `( Pair String )` and its String undropped.
// Closed: as for the non-generic form (gen_member, __mb_tmp_flag).
// main (before this PR): LeakSanitizer, one String per round.
// map: §7.1 | A2 | runs-clean | - | agora #474: a field read off a field taken from a generic call's struct result; the taken struct was never dropped (leak)
$ `stdlib/core/string.nu`

: Pair [T] { T a i b }
: Box1 [T] { ( Pair T ) v }

@ boxit [T] ( Pair T ) p → ( Box1 T ) { ^ @ ( Box1 T ) { p } }

@ once i k → i {
    : i n . . ( boxit [String] @ ( Pair String ) { ( string_from `a string long enough to be on the heap, and then some more bytes` ) k } ) v b
    ^ n
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 10 { = t + t ( once k ) = k + k 1 }
    ( nurl_println_int t )
    ^ 0
}
