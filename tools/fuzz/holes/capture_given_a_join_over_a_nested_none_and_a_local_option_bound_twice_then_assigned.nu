// capture_given_a_join_over_a_nested_none_and_a_local_option_bound_twice_then_assigned: `: ??P e ? == k 0 ( idpp a ) ( idpp b )  : ??P e2 e  = cap e2` in a closure, a = Some(None) of a ??P with P owning two Strings, b a Some(Some); both runs.
// Closed (AGORA-965): a null key is asked of the side the value holds, through nested options (__ntv_val): Some(None) owns nothing, so it takes over no owner and b releases its own (the keyed takeover; `: e2 e` is a __jalias cursor).
// main 3ac7f6e: LeakSanitizer: b taken over with Some(None), never released.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given a join over a nested None and a local option, bound twice
$ `stdlib/core/string.nu`

: P { String name String extra }

@ idpp ? ? P a → ?? P { ^ a }

@ mkpp s t → ?? P { ^ @ ?? P { T @ ?P { T @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra part` ) ) } } } }

@ show ? ? P o → v { ?? o { T q → { ?? q { T p → ( nurl_println ( string_data . p extra ) ) F → ( nurl_println `inner none` ) } } F → ( nurl_println `none` ) } }

@ run i k → v {
    : ~ ? ? P cap ( mkpp `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?? P a @ ?? P { T @ ?P { F } }
        : ?? P b ( mkpp `closure b local long enough for heap ok` )
        : ?? P e ? == k 0 ( idpp a ) ( idpp b )
        : ?? P e2 e
        = cap e2
    }
    ( f )
    ( show cap )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
