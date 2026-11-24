// return_of_a_call_lending_a_local_or_a_parameter_is_the_callers_own_runs_clean: `^ ( pick x p k )`, pick handing back the local x on one run and the parameter p on the other
// Closed: `^ ( g … )` that copies the result on every run on which `g` lent (it may be a local the frame drops) hands back its own value: its summary names none of the arguments `g` could hand back (ret_call_owned_all), so the caller releases the copy.
// main 9ddac8cbd: accepted; LeakSanitizer: the copy leaks on both runs (its summary said it lent p).
// map: §7.6 | A2 | runs-clean | - | AGORA-1004: `^ ( pick x p k )`, pick handing back the local x on one run and the parameter p on the other
$ `stdlib/core/string.nu`

@ pick String a String b i k → String {
    ? == k 0 { ^ a } {}
    ^ b
}

@ esc String p i k → String {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( pick x p k )
}

@ main → i {
    : String p ( string_from `the caller's value, long enough for the heap` )
    : String a ( esc p 0 )
    : String b ( esc p 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data p ) )
    ^ 0
}
