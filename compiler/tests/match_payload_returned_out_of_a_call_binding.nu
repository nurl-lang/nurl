// match_payload_returned_out_of_a_call_binding.nu — `: Msg m ( mk ) ?? m {
// Both c → { ^ c } … }`: the payload handed back is taken out of `m` on the
// runs where `m` owns its value — also when `m`'s drop flag is the one a call
// answering whether it lent its result set (agora #545; before, `m` released
// the payload the caller had been handed, and the caller read freed memory).
$ `stdlib/core/string.nu`

: | Msg { Both String  Nil }
: | Rows { Some [i  None }

@ mk → Msg { ^ @ Msg { Both ( string_from `a long enough string to live on the heap, yes` ) } }
@ second → String {
    : Msg m ( mk )
    ?? m {
        Both c → { ^ c }
        Nil → { ^ ( string_from `none` ) }
    }
}

@ mkr → Rows { ^ @ Rows { Some [i | 4 5 6] } }
@ third → [i {
    : Rows m ( mkr )
    ?? m {
        Some c → { ^ c }
        None → { ^ [i | 0] }
    }
}

@ main → i {
    : String a ( second )
    ( nurl_println ( string_data a ) )
    : [i r ( third )
    ~ x r { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
