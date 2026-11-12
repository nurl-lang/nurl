// drop_owner_given_back_its_value_through_a_forwarder_runs_clean: as drop_owner_given_back_its_value_runs_clean, through a forwarder declared above its callee
// Closed: a struct with a `% Drop` of its own is keyed by its first owned handle field (__udrop_struct_keyable): it cannot be copied, so the buffer is its own, and `= o ( f0 o )` keeps o's value on the runs the call hands it back (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: as that probe, through a forwarder above its callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/box.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f1 R p → R { ^ ( f0 p ) }

@ f0 R p → R { ^ p }

@ main → i { : ~ R o @ R { ( string_from `an R string long enough for the heap buffer` ) 1 } = o ( f1 o ) ( nurl_println ( string_data . o s ) ) ^ 0 }
