// closure_in_a_scoped_block_named_like_an_outer_closure_releases_its_env: a capturing closure `f` bound in a loop body, in a `?` arm and in a `: i n { … }` block, beside an outer closure `f`; and a closure bound twice under one name in one scope.
// Closed: the owned-closure list is keyed by the binding's owner slot, not its name (__cenv_key). By name the inner `f` was taken for the outer one: the list's word was already there, the block's drain kept every name that predated the block, and the inner closure's environment was released by nobody (agora #614).
// main 2498b4e: accepted; LeakSanitizer: the inner closure's env and the String it captured, once per run.
// map: §7.4 | A2 | runs-clean | - | agora #614: a capturing closure bound in a scoped block under the name of an outer closure
$ `stdlib/core/string.nu`

@ mk String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    : ~ i total 0
    : ~ i k 0
    ~ < k 2 {
        : ( @ i i ) f \ i x → i { ^ + + x 1 ( string_len tag ) }
        = total + total ( f k )
        = k + k 1
    }
    : i r { : ( @ i i ) f \ i x → i { ^ + + x 1000 ( string_len tag ) } ( f 2 ) }
    ? > r 0 {
        : ( @ i i ) f \ i x → i { ^ + + x 7 ( string_len tag ) }
        = total + total ( f 1 )
    } {}
    : ( @ i i ) g \ i x → i { ^ + x ( string_len tag ) }
    : ( @ i i ) g ( mk tag )
    ( nurl_println_int + + total r + ( f 3 ) ( g 1 ) )
    ^ 0
}
