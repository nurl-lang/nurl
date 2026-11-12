// rc_owner_given_back_its_share_through_a_generic_forwarder_runs_clean: as rc_owner_given_back_its_share_through_a_forwarder_above_its_callee_runs_clean, both functions generic
// Closed: gen_assign's keep-same test keys a one-pointer library handle by that pointer (__ud_keyable now agrees with mem_identity_key, __libh_keyable): on the run the call hands o's own share back, o keeps it (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: as the Rc probe, through generic forwarders
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/box.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f1 [A] A p → A { ^ ( f0 [A] p ) }

@ f0 [A] A p → A { ^ p }

@ main → i { : ~ ( Rc String ) o ( rc_new [String] ( string_from `an rc string long enough for the heap buffer` ) ) = o ( f1 [( Rc String )] o ) ( nurl_println ( string_data ( rc_get [String] o ) ) ) ^ 0 }
