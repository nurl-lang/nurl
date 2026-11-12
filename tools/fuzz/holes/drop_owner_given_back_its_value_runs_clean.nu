// drop_owner_given_back_its_value_runs_clean: `= o ( f0 o )`, `@ f0 R p → R { ^ p }`, R with its own `% Drop`, f0 declared first: o's value was released (no key), then read
// Closed: a struct with a `% Drop` of its own is keyed by its first owned handle field (__udrop_struct_keyable): it cannot be copied, so the buffer is its own, and `= o ( f0 o )` keeps o's value on the runs the call hands it back (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: a `% Drop` owner given back its own value was released and read
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f0 R p → R { ^ p }

@ main → i {
    : ~ R o @ R { ( string_from `an R string long enough for the heap buffer` ) 1 }
    = o ( f0 o )
    ( nurl_println ( string_data . o s ) )
    ^ 0
}
