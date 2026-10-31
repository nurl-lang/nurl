// view_of_a_call_temporary_kept_by_a_callee_leaked_it: a view of a call's temporary argument handed to a callee that keeps it (`( count ( keep names ( first ( string_from … ) ) ) )`, `keep` pushing it into a Vec) leaked the temporary: `keep`'s summary says it may keep the argument, so no call dropped it — and nothing could, with `names` still holding the view.
// Closed: as h378 — a consumer that keeps the view does not consume the temporary, and one nothing consumes is rejected (resolve_view_temps, agora #138).
// v0.79.1: accepted; LeakSanitizer reported the String and its buffer.
// map: §1 | A2 | rejected | h381 | as h378, the view handed to a callee that keeps it (vec_push into a parameter Vec): no call could drop the temporary
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first String s → s { ^ ( string_data s ) }

@ keep ( Vec s ) names s x → i { ( vec_push [s] names x ) ^ ( vec_len [s] names ) }

@ twice i n → i { ^ * n 2 }

@ main → i {
    : ( Vec s ) names ( vec_new [s] )
    ( nurl_println_int ( twice ( keep names ( first ( string_from `a string long enough to own a heap buffer here` ) ) ) ) )
    ( nurl_println ( vec_at [s] names 0 ) )
    ^ 0
}
