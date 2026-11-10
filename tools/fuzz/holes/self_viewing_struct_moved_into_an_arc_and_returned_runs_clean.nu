// self_viewing_struct_moved_into_an_arc_and_returned_runs_clean: agora #600 — the self-viewing struct moved into `arc_new` inside the returned value: an Arc's payload is frozen, so what it views of its own fields stays with it (tokenizer's unigram shape)
// Control for agora #600.
// map: §2.10 | A2 | runs-clean | - | agora #600: the self-viewing struct moved into `arc_new` inside the returned value: an Arc's payload is frozen, so what it views of its own fields stays with it (tokenizer's unigram shape)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Tk { ( Vec String ) arena ( Vec s ) idx }
: H { ( Arc Tk ) a }

@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}

@ fill Tk t → v {
    ( put . t arena . t idx ( string_from `the first key, long enough for the heap` ) )
}

@ make → H {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) }
    ( fill t )
    ^ @ H { ( arc_new [Tk] t ) }
}

@ main → i {
    : H h ( make )
    ( nurl_println ( vec_at [s] . ( arc_get [Tk] . h a ) idx 0 ) )
    ^ 0
}
