// option_owner_given_a_call_that_may_lend_itself_or_a_fresh_temporary: agora #412 — `= o ( pick o ( mk … ) k )`: the other argument is a fresh value the call is handed (the `or a default` idiom, the shape the fix must keep)
// Closed: a temporary the call is handed is copied where the callee lends it: only arguments that may lend count (__lend_pos_unnamed, agora #412).
// main: accepted, ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pick o ( mk … ) k )`: the other argument is a fresh value the call is handed (the `or a default` idiom, the shape the fix must keep)
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( pick o ( mk `a temporary value long enough for heap` ) k )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
