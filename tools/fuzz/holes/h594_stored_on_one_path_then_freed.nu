// H594: agora #160 — a value stored into an owner on some paths or iterations (stored_on_one_path_then_freed).
// Closed: a store survives joins and loop back-edges (agora #160).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : b c == ( nurl_str_len `a` ) 1
    : String s ( mk )
    : ( Vec String ) v ( vec_new [String] )
    ? c { ( vec_push [String] v s ) } {}
    ( string_free s )
    ( vec_free [String] v )
    ^ 0
}
