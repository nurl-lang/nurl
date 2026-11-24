// return_of_a_call_lending_a_local_a_parameter_or_a_fresh_value_is_the_callers_own_runs_clean: `^ ( pick3 x p k )`, pick3 handing back the local x, the parameter p or a fresh value
// Closed: `^ ( g … )` that copies the result on every run on which `g` lent (it may be a local the frame drops) hands back its own value: its summary names none of the arguments `g` could hand back (ret_call_owned_all), so the caller releases the copy; a fresh value is handed on as it is.
// main 9ddac8cbd: accepted; LeakSanitizer: the copy leaks on the runs that lent.
// map: §7.6 | A2 | runs-clean | - | AGORA-1004: `^ ( pick3 x p k )`, pick3 handing back the local x, the parameter p or a fresh value
$ `stdlib/core/string.nu`

@ pick3 String a String b i k → String {
    ? == k 0 { ^ a } {}
    ? == k 1 { ^ b } {}
    ^ ( string_from `a fresh value long enough for the heap` )
}

@ esc String p i k → String {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( pick3 x p k )
}

@ main → i {
    : String p ( string_from `the caller's value, long enough for the heap` )
    : String a ( esc p 0 )
    : String b ( esc p 1 )
    : String c ( esc p 2 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data c ) )
    ^ 0
}
