// function_clears_its_parameters_element_bound_first: a function binds an element of its parameter to a local and hands it to a clearing function, while the caller still reads a String inside that element.
// Closed: what a callee drops of a local read out of a parameter (bound first, or a ?? payload matched out of one) the function drops of that parameter's elements, as for the element handed on directly (agora #447).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #447: a function binds an element of its parameter to a local and hands it to a clearing function, while the caller still reads a String inside that element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: HS { ( Vec String ) xs }

@ clr ( Vec String ) x → v { ( vec_clear [String] x ) }

@ grow ( Vec String ) x → v { : ~ i n 0 ~ < n 64 { ( vec_push [String] x ( string_from `grown element string long enough for heap` ) ) = n + n 1 } }

@ rd ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ top ( Vec ( Vec String ) ) vv → v { : ( Vec String ) e ( vec_at [( Vec String )] vv 0 ) ( clr e ) }

@ main → i {
    : ( Vec ( Vec String ) ) outer ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] outer ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] outer 0 ) ( string_from `another element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] outer 0 ) 0 )
    ( top outer )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
