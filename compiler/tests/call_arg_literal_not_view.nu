// call_arg_literal_not_view.nu — a literal built from a pointer parameter's
// field and handed straight to a call does not make the function a view.
//
// `?? ( flush @ Fh { . w fh } ) { … F _ → { ^ ( err … ) } }`: the literal
// (a pointer read out of the parameter `w`) marked the whole function as
// returning a view of its parameter (g_fn_ret_view), so every caller took
// its fresh error String for a borrow and never dropped it — and so did
// their callers that handed the error up (packages/gguf's writer). The
// aggregate goes to the callee, not back to this function's caller.

$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Fh { s raw }

: W { s fh i phase }

@ flush Fh f → !v i { ? == # i . f raw 0 { ^ @ !v i { F 1 } } {} ^ @ !v i { T 0 } }

@ err s msg → !v String { ^ @ !v String { F ( string_from msg ) } }

@ w_flush * W w → !v String {
    ?? ( flush @ Fh { . w fh } ) {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ ( err `flush failed` ) }
    }
}

@ data * W w → !v String {
    ? != . w phase 1 { ^ ( err `not in data phase` ) } {}
    ?? ( w_flush w ) {
        T _ → {}
        F e → { ^ @ !v String { F e } }
    }
    ^ @ !v String { T 0 }
}

@ main → i {
    : *W w # *W ( nurl_alloc 16 )
    = . w fh # s 0
    : i l0 ( live )
    : ~ i n 0
    : ~ i k 0
    ~ < k 10 {
        = . w phase % k 2
        ?? ( data w ) { T _ → {} F e → { = n + n ( string_len e ) } }
        = k + k 1
    }
    ( nurl_print_int n ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ( nurl_free # s w )
    ^ 0
}
