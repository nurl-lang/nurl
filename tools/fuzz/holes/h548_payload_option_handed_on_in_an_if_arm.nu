// H548: agora #170 — a `??` arm's payload over an option binding (payload_option_handed_on_in_an_if_arm).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_opt sink ? String o → v {}

@ main → i {
    : b c == ( nurl_str_len `a` ) 1
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ? c { ( take_opt o ) } {}
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ^ 0
}
