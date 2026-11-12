// rc_owner_given_back_its_share_through_a_forwarder_above_its_callee_runs_clean: `= o ( f1 o )`, f1 a forwarder declared above f0 `^ p`, o an `( Rc String )`: no keep-same test was emitted (Rc had no key there), o's share was released while o went on to hold it
// Closed: gen_assign's keep-same test keys a one-pointer library handle by that pointer (__ud_keyable now agrees with mem_identity_key, __libh_keyable): on the run the call hands o's own share back, o keeps it (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: `= o ( f1 o )` through a forwarder above its callee freed an Rc owner's share
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ f1 ( Rc String ) p → ( Rc String ) { ^ ( f0 p ) }

@ f0 ( Rc String ) p → ( Rc String ) { ^ p }

@ main → i {
    : ~ ( Rc String ) o ( rc_new [String] ( string_from `an rc string long enough for the heap buffer` ) )
    = o ( f1 o )
    ( nurl_println ( string_data ( rc_get [String] o ) ) )
    ^ 0
}
