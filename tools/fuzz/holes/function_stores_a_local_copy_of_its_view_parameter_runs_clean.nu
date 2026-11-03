// function_stores_a_local_copy_of_its_view_parameter_runs_clean: a function copies its view parameter into a local and stores it into an inout struct, read while the caller's String lives.
// Must keep compiling and running clean beside agora #346's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #346: a function copies its view parameter into a local and stores it into an inout struct, read while the caller's String lives
$ `stdlib/core/string.nu`

: V { s v }

@ setw inout V w s p → v {
    : s t p
    = w @ V { t }
}

@ main → i {
    : String b ( string_from `a string that outlives the holder, long enough for the heap` )
    : ~ V w @ V { `lit` }
    ( setw w ( string_data b ) )
    ( nurl_println . w v )
    ^ 0
}
