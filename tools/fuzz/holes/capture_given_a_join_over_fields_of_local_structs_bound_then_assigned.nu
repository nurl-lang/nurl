// capture_given_a_join_over_fields_of_local_structs_bound_then_assigned: `: String e ? == k 0 ( ex a ) ( ex b )  = o e` in a closure, ex handing back `. p extra` of a local struct; both runs.
// Closed (AGORA-967): an owner whose key does not name what the binding holds (a struct a call lent a field of) is not taken over; the binding is given a copy where it owns nothing, and each struct releases its own.
// main c4c0f35: LeakSanitizer: both structs taken over whole, only the field released.
// map: §7.4 | A2 | runs-clean | - | AGORA-967: a capture given by name a `:` join over fields lent out of local structs
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → P { ^ @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra` ) ) } }

@ ex P p → String { ^ . p extra }

@ run i k → v {
    : ~ String o ( string_from `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : P a ( mk `closure a local long enough for heap ok` )
        : P b ( mk `closure b local long enough for heap ok` )
        : String e ? == k 0 ( ex a ) ( ex b )
        = o e
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
