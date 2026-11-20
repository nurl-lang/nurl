// closure_over_a_parameters_vec_and_a_local_handed_back_then_the_vec_freed: AGORA-877 — a closure literal handed back that captures a parameter's Vec beside a local of its own; the caller frees the Vec and runs it
// Closed (ownership engine): a closure literal handed back as it is copies in only its own frame's bindings; a parameter's handle stays in its env as a view of the caller's value, lent through the result (__closure_owned_at). The walk refused it already; the engine accepted it.
// Engine before this PR: runs-clean; --no-borrowck -fsanitize=address: SEGV in vec_get, called from the closure.
// map: §2.11 | A2 | rejected | - | AGORA-877: a returned closure over a parameter's Vec and a local, run after the Vec was freed
$ `stdlib/core/vec.nu`

@ mk ( Vec i ) v → ( @ ?i i ) {
    : ( Vec i ) w ( vec_new [i] )
    ^ \ i cmd → ?i {
        ? > ( vec_len [i] w ) cmd { ^ @ ?i { F 0 } } {}
        ^ ( vec_get [i] v cmd )
    }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ ?i i ) it ( mk v )
    ( vec_free [i] v )
    : ?i g ( it 0 )
    ?? g { T x → { ( nurl_println_int x ) } F → { ( nurl_println `none` ) } }
    ^ 0
}
