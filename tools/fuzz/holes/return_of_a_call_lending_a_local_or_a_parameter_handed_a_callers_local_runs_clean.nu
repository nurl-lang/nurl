// return_of_a_call_lending_a_local_or_a_parameter_handed_a_callers_local_runs_clean: a caller hands its own local to `esc`, which returns `^ ( pick x p k )`
// Closed: `^ ( g … )` that copies the result on every run on which `g` lent (it may be a local the frame drops) hands back its own value: its summary names none of the arguments `g` could hand back (ret_call_owned_all), so the caller releases the copy; the caller's local goes as usual.
// main 9ddac8cbd: accepted; LeakSanitizer: the copy leaks.
// map: §7.6 | A2 | runs-clean | - | AGORA-1004: a caller hands its own local to `esc`, which returns `^ ( pick x p k )`
$ `stdlib/core/string.nu`

@ pick String a String b i k → String {
    ? == k 0 { ^ a } {}
    ^ b
}

@ esc String p i k → String {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( pick x p k )
}

@ g i k → String {
    : String y ( string_from `a caller local long enough for the heap` )
    ^ ( esc y k )
}

@ main → i {
    : String a ( g 0 )
    : String b ( g 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
