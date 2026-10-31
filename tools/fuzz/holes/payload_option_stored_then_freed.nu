// payload_option_stored_then_freed: agora #170 — a `??` arm's payload over an option binding (payload_option_stored_then_freed).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h544 | agora #170: payload_option_stored_then_freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec ? String ) v ( vec_new [? String] )
    ( vec_push [? String] v @ ?String { T ( mk ) } )
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( vec_push [? String] v o )
            ( vec_free [? String] v )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}
