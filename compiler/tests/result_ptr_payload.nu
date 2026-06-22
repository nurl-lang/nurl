// result_ptr_payload.nu — regression: unwrapping a bare pointer (`*T`)
// Ok-payload from a `! *T E` result.
//
// The Ok-arm reconstruction routed on the LLVM type's LEADING char: a
// `%`-prefixed type went to the struct-HANDLE path. But a NURL `*Struct`
// lowers to `%Struct*` — `%`-prefixed AND `*`-suffixed — so it was
// misclassified as a handle, reconstructed nothing, and the binding got
// the raw i64 slot as garbage. The fix routes on the trailing `*`
// (pointer) instead. Without it, `. p a` below reads through a corrupt
// pointer (crash / wrong value).

$ `stdlib/core/string.nu`

: | Boom { Bang }

: Box { i a i b }

@ mk_ok i n → !*Box Boom {
    : *Box p # *Box ( nurl_alloc Z Box )
    = . p a n
    = . p b * n 2
    ^ @ !*Box Boom { T p }
}

@ mk_err → !*Box Boom {
    ^ @ !*Box Boom { F @ Boom { Bang } }
}

@ main → i {
    : !*Box Boom r ( mk_ok 21 )
    ?? r {
        T p → {
            ( nurl_print `a=` ) ( nurl_print_int . p a )
            ( nurl_print `b=` ) ( nurl_print_int . p b )
            ( nurl_free # s p )
        }
        F e → ( nurl_print `unexpected err\n` )
    }

    : !*Box Boom r2 ( mk_err )
    ?? r2 {
        T p → ( nurl_print `unexpected ok\n` )
        F e → ( nurl_print `got err\n` )
    }
    ^ 0
}
