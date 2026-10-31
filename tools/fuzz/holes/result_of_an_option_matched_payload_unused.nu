// result_of_an_option_matched_payload_unused: agora #158 — a result whose payload or error is an option (result_of_an_option_matched_payload_unused).
// Closed: the result registers its twin past the inner braces (agora #158).
// v0.80.0: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h570 | agora #158: result_of_an_option_matched_payload_unused
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ mkr → !?String i { ^ @ !?String i { T @ ?String { T ( mk ) } } }

@ main → i {
    : ~ ( Vec i ) keep ( vec_new [i] )
    : !?String i r ( mkr )
    ?? r { T o → { ( vec_push [i] keep 1 ) } F e → {} }
    ^ 0
}
