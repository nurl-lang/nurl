// capture_given_a_join_over_fields_of_literal_local_structs_bound_then_assigned: as capture_given_a_join_over_fields_of_local_structs_bound_then_assigned, the structs built by literals (no drop flag of their own); both runs.
// Closed (AGORA-967): a local an arm's lending call lends part of is recorded on the join binding (`__jparts`); handed by name to a binding that outlives it, the value is copied there.
// main c4c0f35: AddressSanitizer: heap-use-after-free (o kept a field its closure released).
// map: §7.4 | A2 | runs-clean | - | AGORA-967: a capture given by name a `:` join over fields lent out of literal-built local structs
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → P { ^ @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra` ) ) } }

@ ex P p → String { ^ . p extra }

@ run i k → v {
    : ~ String o ( string_from `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : P a @ P { ( string_from `lit a name long enough for heap ok ok` ) ( string_from `lit a extra long enough for heap ok` ) }
        : P b @ P { ( string_from `lit b name long enough for heap ok ok` ) ( string_from `lit b extra long enough for heap ok` ) }
        : String e ? == k 0 ( ex a ) ( ex b )
        = o e
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
