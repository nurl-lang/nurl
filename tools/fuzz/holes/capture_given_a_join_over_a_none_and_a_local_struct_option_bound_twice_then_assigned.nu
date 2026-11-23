// capture_given_a_join_over_a_none_and_a_local_struct_option_bound_twice_then_assigned: `: ?P e ? == k 0 ( idp a ) ( idp b )  : ?P e2 e  = cap e2` in a closure, a = None, b a Some of a struct owning two Strings; both runs.
// Closed (AGORA-965): a None owns nothing whatever its payload type (__ud_null_triv_rt), so its null key takes over no owner (the keyed takeover; `: e2 e` is a __jalias cursor).
// main 3ac7f6e: LeakSanitizer: b taken over with the None, never released.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given a join over a None and a local struct option, bound twice
$ `stdlib/core/string.nu`

: P { String name String extra }

@ idp ? P a → ?P { ^ a }

@ mkp s t → ?P { ^ @ ?P { T @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra part` ) ) } } }

@ show ? P o → v { ?? o { T p → ( nurl_println ( string_data . p extra ) ) F → ( nurl_println `none` ) } }

@ run i k → v {
    : ~ ? P cap ( mkp `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?P a @ ?P { F }
        : ?P b ( mkp `closure b local long enough for heap ok` )
        : ?P e ? == k 0 ( idp a ) ( idp b )
        : ?P e2 e
        = cap e2
    }
    ( f )
    ( show cap )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
