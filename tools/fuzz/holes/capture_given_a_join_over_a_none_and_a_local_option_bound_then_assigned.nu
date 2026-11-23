// capture_given_a_join_over_a_none_and_a_local_option_bound_then_assigned: as capture_given_a_join_over_literal_local_options_bound_then_assigned, with a = None: on the run the join selects it the value's key is null, which names no owner.
// Closed (AGORA-965): a null key of a value that then owns nothing (None, an empty String: __ud_null_trivial) takes over no owner, and each releases its own; taken over all, the other option leaked.
// main c4c0f35: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given by name a `:` join over a None and a local option
$ `stdlib/core/string.nu`

@ idq ? String a → ?String { ^ a }

@ run i k → v {
    : ~ ? String cap @ ?String { T ( string_from `outer value long enough for the heap here` ) }
    : ~ ( @ v ) f \ → v {
        : ?String a @ ?String { F }
        : ?String b @ ?String { T ( string_from `option b long enough for the heap ok ok` ) }
        : ?String e ? == k 0 ( idq a ) ( idq b )
        = cap e
    }
    ( f )
    ?? cap { T s → ( nurl_println ( string_data s ) ) F → {} }
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
