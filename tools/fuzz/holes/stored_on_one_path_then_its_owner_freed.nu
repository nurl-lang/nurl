// stored_on_one_path_then_its_owner_freed: agora #160 — a value stored into an owner on some paths or iterations (stored_on_one_path_then_its_owner_freed).
// Closed: a store survives joins and loop back-edges (agora #160).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h590 | agora #160: stored_on_one_path_then_its_owner_freed
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
    ( vec_free [String] v )
    ( nurl_println ( string_data s ) )
    ^ 0
}
