// H553: agora #170 — a `??` arm's payload over an option binding (vec_payload_option_handed_on).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_ov sink ? ( Vec String ) o → v {}

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( mk ) )
    : ~ ? ( Vec String ) ov @ ?( Vec String ) { T v0 }
    ?? ov {
        T v → {
            ( take_ov ov )
            ( nurl_println ( nurl_str_int ( vec_len [String] v ) ) )
        }
        F → {}
    }
    ^ 0
}
