// vec_owner_lent_a_local_given_back_itself_then_returned_runs_clean: a Vec owner
// Closed: an `=` that hands the binding back to itself keeps what its old value may be a lend of (mem_note_assign_lend), so `^ o` copies a lend of a local as it does without the self-handback (agora #873; found by its skeptic pass).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | AGORA-873: a Vec owner
$ `stdlib/core/vec.nu`

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ back → ( Vec i ) {
    : ~ ( Vec i ) loc ( vec_new [i] )
    ( vec_push [i] loc 7 )
    : ~ ( Vec i ) o ( vec_new [i] )
    = o ( vid loc )
    = o ( vid o )
    ^ o
}

@ main → i {
    : ~ ( Vec i ) r ( back )
    ( nurl_println ( nurl_str_int ( vec_at [i] r 0 ) ) )
    ^ 0
}
