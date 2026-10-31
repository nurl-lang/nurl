// result_payload_replaced_by_an_inout_callee: agora #170 — a `??` arm's payload over an option binding (result_payload_replaced_by_an_inout_callee).
// Closed: the payload is a cursor over the option (agora #170).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h547 | agora #170: result_payload_replaced_by_an_inout_callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ res_clear inout ! String i r → v { = r @ !String i { F 0 } }

@ main → i {
    : ~ ! String i r @ !String i { T ( mk ) }
    ?? r {
        T x → {
            ( res_clear r )
            ( nurl_println ( string_data x ) )
        }
        F e → {}
    }
    ^ 0
}
