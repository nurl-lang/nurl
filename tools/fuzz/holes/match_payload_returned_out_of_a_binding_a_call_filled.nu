// match_payload_returned_out_of_a_binding_a_call_filled: agora #545 — `: Msg m ( mk ) ?? m { Both c → { ^ c } … }`: the payload went back to the caller while `m` still released it, whenever `mk` is a call that answers at run time whether its result was lent (m's drop flag was that answer, and the take did not clear it).
// Closed: the match takes the payload out of `m` on the runs where `m` owns its value, whichever flag says so.
// main (before this PR): AddressSanitizer, heap-use-after-free in main.
// map: §7.6 | A2 | runs-clean | - | agora #545: a payload returned out of a match on a binding a call filled was released by the binding too (UAF)
$ `stdlib/core/string.nu`

: | Msg { Both String Nil }

@ mk → Msg { ^ @ Msg { Both ( string_from `a long enough string to live on the heap, yes` ) } }

@ second → String {
    : Msg m ( mk )
    ?? m {
        Both c → { ^ c }
        Nil → { ^ ( string_from `none` ) }
    }
}

@ main → i {
    : String a ( second )
    ( nurl_println ( string_data a ) )
    ^ 0
}
