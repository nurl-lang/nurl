// option_owner_given_back_its_own_value_by_a_call: agora #342 — a `: ~ ?String` owner given back its own value by a function that returns its argument (`= o ( id o )`): its old value was dropped and then held.
// Closed: `= o ( f o )` with f possibly handing its argument back gates o's old value's drop on f's per-call ownership answer for an option or a result of an owning value too, as it already did for a String (agora #342).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #342: a `
$ `stdlib/core/string.nu`

@ id ? String x → ?String { ^ x }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( id o )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
