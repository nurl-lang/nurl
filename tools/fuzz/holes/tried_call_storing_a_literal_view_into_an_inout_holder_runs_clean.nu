// tried_call_storing_a_literal_view_into_an_inout_holder_runs_clean: the tried call stores a view of a literal into the inout holder, then fails.
// Control for agora #406: checking the way out after the tried call refuses nothing safe.
// map: §2.10 | A2 | runs-clean | - | agora #406: the tried call stores a view of a literal into the inout holder, then fails
$ `stdlib/core/string.nu`

: W { s v }
: | E { Bad i }

@ setw inout W w s v i k → !i E {
    = w @ W { v }
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : i x \ ( setw w `a literal view` k )
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `start` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
