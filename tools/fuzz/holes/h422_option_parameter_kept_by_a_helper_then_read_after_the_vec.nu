// H422: as h421, through a helper that pushes its option parameter into a
// Vec parameter.
// Closed: as h421 (agora #149).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ( Vec ? String ) out ? String o → v { ( vec_push [? String] out o ) }

@ main → i {
    : ( Vec ? String ) out ( vec_new [? String] )
    : ?String o @ ?String { T ( mk ) }
    ( f out o )
    ( vec_free [? String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
