// H413: an option parameter's payload put in a struct literal the function
// hands back (`T s → @ W { s }`); the caller released the result's field and
// read its option.
// Closed: the result lends the parameter's payload, so its field is a
// borrow's, which may not be handed to a callee that takes it (agora #145's
// `pendfx` rule).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: W { String w }

@ f ? String o → W { ^ ?? o { T s → @ W { s } F → @ W { ( mk ) } } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : W w ( f o )
    ( string_free . w w )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
