// return_of_a_call_lending_a_local_or_a_parameter_bound_and_handed_back_runs_clean: `: String r ( esc q k )  ^ r` over `esc`, which returns `^ ( pick x p k )`
// Closed: `^ ( g … )` that copies the result on every run on which `g` lent (it may be a local the frame drops) hands back its own value: its summary names none of the arguments `g` could hand back (ret_call_owned_all), so the caller releases the copy; a binding of it hands it back as its own.
// main 9ddac8cbd: accepted; LeakSanitizer: the copy leaks.
// map: §7.6 | A2 | runs-clean | - | AGORA-1004: `: String r ( esc q k )  ^ r` over `esc`, which returns `^ ( pick x p k )`
$ `stdlib/core/string.nu`

@ pick String a String b i k → String {
    ? == k 0 { ^ a } {}
    ^ b
}

@ esc String p i k → String {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( pick x p k )
}

@ h String q i k → String {
    : String r ( esc q k )
    ^ r
}

@ main → i {
    : String p ( string_from `the caller value long enough for the heap` )
    : String a ( h p 0 )
    : String b ( h p 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
