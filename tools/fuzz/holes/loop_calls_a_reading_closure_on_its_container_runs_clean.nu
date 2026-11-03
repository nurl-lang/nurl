// loop_calls_a_reading_closure_on_its_container_runs_clean: a '~' loop over a Vec calls a closure binding that only reads its parameter with the Vec, then reads the loop's element.
// Must keep compiling and running clean beside agora #436's rule.
// main's compiler: compiled, ran clean.
// map: §2.5 | A2 | runs-clean | - | agora #436: a '~' loop over a Vec calls a closure binding that only reads its parameter with the Vec, then reads the loop's element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [String] xs ( string_from `another element string long enough for the heap` ) )
    : ( @ v ( Vec String ) ) f \ ( Vec String ) y → v { ( nurl_println_int ( vec_len [String] y ) ) }
    ~ x xs {
        ( f xs )
        ( nurl_println_int ( string_len x ) )
    }
    ^ 0
}
