// H593: agora #160 — a value stored into an owner on some paths or iterations (stored_before_a_break_then_its_owner_freed).
// Closed: a store survives joins and loop back-edges (agora #160).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : String s ( mk )
    : ( Vec String ) v ( vec_new [String] )
    : ~ i k 0
    ~ < k 3 {
        ? == k 1 {
            ( vec_push [String] v s )
            break
        } {}
        = k + k 1
    }
    ( vec_free [String] v )
    ( nurl_println ( string_data s ) )
    ^ 0
}
