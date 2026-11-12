// inout_param_given_a_string_field_of_a_borrowed_param_runs_clean: `= dst . x name` with dst an `inout String` and x a by-value struct parameter
// Closed: a field read of a binding is a lend of its owner: stored into an `inout` place it is copied there, the old value going, as `= io . w s` of a local already was (agora #697).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #697: `= dst . x name` with dst an `inout String` and x a by-value struct parameter
$ `stdlib/core/string.nu`

: App { String name i n }

@ refill inout String dst App x → v { = dst . x name }

@ main → i {
    : App a @ App { ( string_from `a name long enough for the heap buffer here` ) 1 }
    : ~ String c ( string_from `the old value, long enough for a heap buffer` )
    ( refill c a )
    ^ - ( string_len c ) ( string_len . a name )
}
