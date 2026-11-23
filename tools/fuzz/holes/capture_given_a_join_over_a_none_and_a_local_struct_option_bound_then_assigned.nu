// capture_given_a_join_over_a_none_and_a_local_struct_option_bound_then_assigned: `: ?P e ? == k 0 ( idp a ) ( idp b )  = cap e` in a closure, a = None and b a Some of a struct owning two Strings; both runs.
// Closed (AGORA-965): a null key is asked of the side the value holds (__ud_null_triv_rt): a None owns nothing, whatever its payload type, so it takes over no owner and b releases its own.
// main 3ac7f6e: LeakSanitizer: the Some owner taken over with the None, never released.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given by name a `:` join over a None and a local option of a struct
$ `stdlib/core/string.nu`

: P { String name String extra }

@ idp ? P a → ?P { ^ a }

@ mkp s t → ?P { ^ @ ?P { T @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra part` ) ) } } }

@ run i k → v {
    : ~ ? P cap ( mkp `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?P a @ ?P { F }
        : ?P b ( mkp `closure b local long enough for heap ok` )
        : ?P e ? == k 0 ( idp a ) ( idp b )
        = cap e
    }
    ( f )
    ?? cap { T p → ( nurl_println ( string_data . p extra ) ) F → ( nurl_println `none` ) }
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
