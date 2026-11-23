// capture_given_a_join_over_literal_local_options_bound_then_assigned: `: ?String e ? == k 0 ( idq a ) ( idq b )  = cap e` in a closure, a and b local options built by literals (no drop flag of their own), idq handing back its argument; both runs.
// Closed (AGORA-965): a `:` join is a cursor over a local its arm's call lends whole (an argument of the lending call, of the join's own type), as a single call's result is; `= cap e` takes over the one the join selected, by its key.
// main c4c0f35: AddressSanitizer: heap-use-after-free reading cap after the closure returned.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given by name a `:` join over literal-built local options' lends
$ `stdlib/core/string.nu`

@ idq ? String a → ?String { ^ a }

@ run i k → v {
    : ~ ? String cap @ ?String { T ( string_from `outer value long enough for the heap here` ) }
    : ~ ( @ v ) f \ → v {
        : ?String a @ ?String { T ( string_from `option a long enough for the heap ok ok` ) }
        : ?String b @ ?String { T ( string_from `option b long enough for the heap ok ok` ) }
        : ?String e ? == k 0 ( idq a ) ( idq b )
        = cap e
    }
    ( f )
    ?? cap { T s → ( nurl_println ( string_data s ) ) F → {} }
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
