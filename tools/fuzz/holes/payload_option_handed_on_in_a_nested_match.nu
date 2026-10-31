// payload_option_handed_on_in_a_nested_match: agora #170 — a `??` arm's payload over an option binding (payload_option_handed_on_in_a_nested_match).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h550 | agora #170: payload_option_handed_on_in_a_nested_match
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_opt sink ? String o → v {}

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ?? o {
                T y → { ( take_opt o ) }
                F → {}
            }
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}
