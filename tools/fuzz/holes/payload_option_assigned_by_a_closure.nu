// payload_option_assigned_by_a_closure: agora #170 — a `??` arm's payload over an option binding (payload_option_assigned_by_a_closure).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h557 | agora #170: payload_option_assigned_by_a_closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    : ( @ v ) h \ → v { = o @ ?String { F } }
    ?? o {
        T x → {
            ( h )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}
