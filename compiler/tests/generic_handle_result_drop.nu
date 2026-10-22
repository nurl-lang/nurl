// generic_handle_result_drop.nu — a library handle handed back inside a
// result by a generic function, where nothing but that generic function
// names the handle's instance: `( G String )` comes into being only when
// the instance `get [String]` is compiled — after the caller. The caller
// asked whether the result's payload is a library handle before the
// instance existed, took it for a plain value, and never dropped it (the
// arm binding of `?? ( get … ) { T g → … }` leaked, and with it what the
// handle held). The instance's identity is now recorded when the call's
// result type is computed (compute_generic_ret_ty).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: G [A] { A val i tag }

@ G_drop [A] sink ( G A ) g → v { ( nurl_print `G dropped\n` ) }

: | E { Bad }

@ make [A] ( @ A ) mk → ( G A ) { ^ @ ( G A ) { ( mk ) 1 } }

@ get [A] ( @ A ) mk b ok → !( G A ) E {
    ? ok { ^ @ !( G A ) E { T ( make [A] mk ) } } {}
    ^ @ !( G A ) E { F # E Bad }
}

@ main → i {
    : ( @ String ) mk \ → String { ^ ( string_from `payload` ) }
    ?? ( get [String] mk T ) { T g → { ( nurl_print `arm\n` ) } F _ → {} }
    ( nurl_print `after the arm\n` )
    ?? ( get [String] mk F ) { T g → { ( nurl_print `arm\n` ) } F _ → { ( nurl_print `error arm\n` ) } }
    ( nurl_print `end\n` )
    ^ 0
}
