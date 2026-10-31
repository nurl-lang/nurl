// payload_option_replaced_by_an_inout_callee: agora #170 — a `??` arm's payload over an option binding (payload_option_replaced_by_an_inout_callee).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h556 | agora #170: payload_option_replaced_by_an_inout_callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( opt_clear o )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}

@ opt_clear inout ? String o → v { = o @ ?String { F } }
