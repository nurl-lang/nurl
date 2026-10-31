// stored_into_one_owner_on_every_iteration: agora #160 — a value stored into an owner on some paths or iterations (stored_into_one_owner_on_every_iteration).
// Closed: a store survives joins and loop back-edges (agora #160).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h591 | agora #160: stored_into_one_owner_on_every_iteration
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
    ~ < k 2 {
        ( vec_push [String] v s )
        = k + k 1
    }
    ( vec_free [String] v )
    ^ 0
}
