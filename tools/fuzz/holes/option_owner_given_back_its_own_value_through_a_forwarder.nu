// option_owner_given_back_its_own_value_through_a_forwarder: agora #342 — the same through a forwarder of that function.
// Closed: `= o ( f o )` with f possibly handing its argument back gates o's old value's drop on f's per-call ownership answer for an option or a result of an owning value too, as it already did for a String (agora #342).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #342: the same through a forwarder of that function
$ `stdlib/core/string.nu`

@ id ? String x → ?String { ^ x }

@ fwd ? String x → ?String { ^ ( id x ) }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( fwd o )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
