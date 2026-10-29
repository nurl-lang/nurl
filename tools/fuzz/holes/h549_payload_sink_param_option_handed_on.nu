// H549: agora #170 — a `??` arm's payload over an option binding (payload_sink_param_option_handed_on).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_opt sink ? String o → v {}

@ f sink ? String o → v {
    ?? o {
        T x → {
            ( take_opt o )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
}

@ main → i { ( f @ ?String { T ( mk ) } ) ^ 0 }
