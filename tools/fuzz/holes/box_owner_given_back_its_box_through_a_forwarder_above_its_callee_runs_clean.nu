// box_owner_given_back_its_box_through_a_forwarder_above_its_callee_runs_clean: as rc_owner_given_back_its_share_through_a_forwarder_above_its_callee_runs_clean, a Box
// Closed: gen_assign's keep-same test keys a one-pointer library handle by that pointer (__ud_keyable now agrees with mem_identity_key, __libh_keyable): on the run the call hands o's own share back, o keeps it (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: as the Rc probe, a Box owner
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ f1 ( Box String ) p → ( Box String ) { ^ ( f0 p ) }

@ f0 ( Box String ) p → ( Box String ) { ^ p }

@ main → i {
    : ~ ( Box String ) o ( box_new [String] ( string_from `a boxed string long enough for the heap buffer` ) )
    = o ( f1 o )
    ( nurl_println ( string_data ( box_get [String] o ) ) )
    ^ 0
}
