// function_hands_its_parameters_element_to_a_reader_runs_clean: a function handing its parameter's lent element to a reader.
// Must keep compiling and running clean beside agora #443's rule.
// main's compiler: compiled, ran clean.
// map: §2.5 | A2 | runs-clean | - | agora #443: a function handing its parameter's lent element to a reader
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ rd ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ my_each ( Vec ( Vec String ) ) vv → i { ^ ( rd ( vec_at [( Vec String )] vv 0 ) ) }

@ main → i {
    : ( Vec ( Vec String ) ) outer ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] outer ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] outer 0 ) ( string_from `another element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] outer 0 ) 0 )
    ( my_each outer )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
