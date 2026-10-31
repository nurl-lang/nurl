// payload_option_replaced_by_a_closure_argument: agora #170 — a `??` arm's payload over an option binding (payload_option_replaced_by_a_closure_argument).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h554 | agora #170: payload_option_replaced_by_a_closure_argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ opt_clear inout ? String o → v { = o @ ?String { F } }

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( run \ → v { ( opt_clear o ) } )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}
