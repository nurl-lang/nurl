// lint_owned_temp.nu — `--lint`: an allocation owned by nothing.
//
// A fresh allocation handed straight to another call's argument list is
// bound to nothing, so nothing ever frees it (docs/MEMORY.md §1). It is
// invisible without LSan and it grows: `ext/http_router.nu` and
// `ext/http_middleware.nu` each leaked one such string PER REQUEST until
// 0.46.0. This reports it at the call site.
//
// The routes by which such a temporary legitimately ends its life must
// stay SILENT: a destructor, a `sink` parameter, an argument the callee
// embeds in an aggregate, an escaping position (`vec_push`), and a callee
// that hands back a VIEW rather than a fresh handle.
//
// Expected: COMPILE OK, warnings for exactly the four `LEAK` lines.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String s }

@ fresh → String { ^ ( string_from `fresh` ) }

@ hold String s → Holder { ^ @ Holder { s } }

@ takes String s → i { ^ ( string_len s ) }

@ view Holder h → String { ^ . h s }

@ silent_cases → i {
    // Destructor: the temporary is consumed.
    ( string_free ( fresh ) )
    // Embedded into an aggregate the callee owns.
    : Holder h ( hold ( fresh ) )
    ( string_free . h s )
    // Pushed into a container — ownership moves into the Vec.
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( fresh ) )
    ( vec_free_with [String] v \ String x → v { ( string_free x ) } )
    // A borrow of a parameter, not a fresh handle.
    : Holder h2 ( hold ( fresh ) )
    : i n ( takes ( view h2 ) )
    ( string_free . h2 s )
    // Bound first, then passed — the whole point of the lint.
    : String bound ( fresh )
    : i m ( takes bound )
    ( string_free bound )
    ^ + n m
}

@ leaking_cases → i {
    : ~ i acc 0
    = acc + acc ( takes ( fresh ) )  // LEAK: String temporary
    = acc + acc ( nurl_str_len ( nurl_str_int 7 ) )  // LEAK: owned i8* temporary
    : String a ( string_from `a` )
    = acc + acc ( takes ( string_clone a ) )  // LEAK: clone owned by nothing
    = acc + acc ( nurl_str_len ( nurl_str_cat `x` `y` ) )  // LEAK: cat result
    ( string_free a )
    ^ acc
}

@ main → i {
    ^ + ( silent_cases ) ( leaking_cases )
}
