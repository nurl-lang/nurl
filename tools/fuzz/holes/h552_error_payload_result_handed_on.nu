// H552: agora #170 — a `??` arm's payload over an option binding (error_payload_result_handed_on).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ take_res sink ! i String r → v {}

@ main → i {
    : ~ ! i String r @ !i String { F ( mk ) }
    ?? r {
        T n → {}
        F e → {
            ( take_res r )
            ( nurl_println ( string_data e ) )
        }
    }
    ^ 0
}
