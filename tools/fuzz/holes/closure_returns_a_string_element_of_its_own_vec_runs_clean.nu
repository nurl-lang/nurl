// closure_returns_a_string_element_of_its_own_vec_runs_clean: a String element of the body's own Vec, handed back: copied.
// Must keep compiling and running clean beside agora #372's rule.
// main's compiler: compiled, ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #372: a String element of the body's own Vec, handed back: copied
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( @ String ) f \ → String {
        : ( Vec String ) cs ( vec_new [String] )
        ( vec_push [String] cs ( string_from `an element name long enough to live on the heap for sure` ) )
        : String c ( vec_at [String] cs 0 )
        ^ c
    }
    : String a ( f )
    ( nurl_println ( string_data a ) )
    ^ 0
}
