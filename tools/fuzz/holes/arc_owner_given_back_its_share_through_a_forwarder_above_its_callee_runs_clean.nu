// arc_owner_given_back_its_share_through_a_forwarder_above_its_callee_runs_clean: as rc_owner_given_back_its_share_through_a_forwarder_above_its_callee_runs_clean, an Arc
// Closed: gen_assign's keep-same test keys a one-pointer library handle by that pointer (__ud_keyable now agrees with mem_identity_key, __libh_keyable): on the run the call hands o's own share back, o keeps it (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: as the Rc probe, an Arc owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/box.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f1 ( Arc String ) p → ( Arc String ) { ^ ( f0 p ) }

@ f0 ( Arc String ) p → ( Arc String ) { ^ p }

@ main → i { : ~ ( Arc String ) o ( arc_new [String] ( string_from `an arc string long enough for the heap buffer` ) ) = o ( f1 o ) ( nurl_println ( string_data ( arc_get [String] o ) ) ) ^ 0 }
