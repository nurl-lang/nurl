// rc_owner_given_back_one_of_two_shares_through_a_forwarder_runs_clean: `= o ( f1 o z T )`, the forwarded callee handing back either share: the keep-same test tells them apart by the control block
// Closed: gen_assign's keep-same test keys a one-pointer library handle by that pointer (__ud_keyable now agrees with mem_identity_key, __libh_keyable): on the run the call hands o's own share back, o keeps it (agora #758).
// main ae5e524: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #758: an Rc owner given back one of two shares through a forwarder
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/box.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f1 ( Rc String ) p ( Rc String ) q b c → ( Rc String ) { ^ ( f0 p q c ) }

@ f0 ( Rc String ) p ( Rc String ) q b c → ( Rc String ) { ? c { ^ p } {} ^ q }

@ main → i { : ~ ( Rc String ) o ( rc_new [String] ( string_from `an rc string long enough for the heap buffer` ) ) : ( Rc String ) z ( rc_new [String] ( string_from `another rc string long enough for the heap` ) ) = o ( f1 o z T ) ( nurl_println ( string_data ( rc_get [String] o ) ) ) ^ 0 }
