// The selftest's program outside C.Elab's subset (formal/C/Elab.lean): a Vec
// of Strings, whose elements are no numbers and no raw text. The verified
// checker accepts it, so its bundle's term is the translator's, and its
// ledger row the one a downgraded bundle must have (nurl-cert_test.sh,
// parts 1 and 2).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string held in a Vec of Strings` ) )
    ^ ( vec_len [String] t )
}
