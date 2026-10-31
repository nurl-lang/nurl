// payload_stored_then_option_handed_on: agora #170 — a `??` arm's payload over an option binding (payload_stored_then_option_handed_on).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h545 | agora #170: payload_stored_then_option_handed_on
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_opt sink ? String o → v {}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( vec_push [String] v x )
            ( take_opt o )
        }
        F → {}
    }
    ( vec_free [String] v )
    ^ 0
}
