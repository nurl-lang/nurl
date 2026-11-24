// return_of_a_call_lending_two_parameters_still_lends_them_runs_clean: guard: `^ ( pick p q k )`, both arguments parameters
// Closed: nothing is copied, so the result is still a lend of p or q (ret_alias 0 1), released by neither caller nor callee twice (control for agora #1004).
// main 9ddac8cbd: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-1004: guard: `^ ( pick p q k )`, both arguments parameters
$ `stdlib/core/string.nu`

@ pick String a String b i k → String {
    ? == k 0 { ^ a } {}
    ^ b
}

@ fwd String p String q i k → String { ^ ( pick p q k ) }

@ main → i {
    : String p ( string_from `the first caller value, long enough for the heap` )
    : String q ( string_from `the second caller value, long enough for the heap` )
    : String a ( fwd p q 0 )
    : String b ( fwd p q 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data p ) )
    ^ 0
}
