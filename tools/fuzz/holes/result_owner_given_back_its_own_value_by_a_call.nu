// result_owner_given_back_its_own_value_by_a_call: agora #342 — a `: ~ !String i` owner given back its own value by a function that returns its argument.
// Closed: `= o ( f o )` with f possibly handing its argument back gates o's old value's drop on f's per-call ownership answer for an option or a result of an owning value too, as it already did for a String (agora #342).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #342: a `
$ `stdlib/core/string.nu`

@ idr ! String i x → !String i { ^ x }

@ main → i {
    : ~ ! String i r @ !String i { T ( string_from `a result value long enough for the heap` ) }
    = r ( idr r )
    ?? r { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    ^ 0
}
