// taken_field_holder_read_for_a_scalar_field_in_a_returned_join_runs_clean: AGORA-929 guard — `^ ? c . h n k` after a sink took `. h buf`: the arm reads a field the take left, accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: a join arm reading a scalar field of a holder whose other field is taken
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ f b c → i {
    : Holder h @ Holder { ( vec_new [u] ) 3 }
    ( vec_push [u] . h buf # u 66 )
    : i k ( take . h buf )
    ^ ? c . h n k
}

@ main → i { ( nurl_println_int ( f T ) ) ^ 0 }
