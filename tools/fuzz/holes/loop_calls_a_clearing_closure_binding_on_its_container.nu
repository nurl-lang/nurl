// loop_calls_a_clearing_closure_binding_on_its_container: a '~' loop over a Vec calls a closure binding that clears its parameter with the Vec, then reads the loop's element.
// Closed: a closure value called inside a '~' loop with the loop's container is decided at module end against its node's closed summary, as a function compiled later is (agora #436).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #436: a '~' loop over a Vec calls a closure binding that clears its parameter with the Vec, then reads the loop's element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [String] xs ( string_from `another element string long enough for the heap` ) )
    : ( @ v ( Vec String ) ) f \ ( Vec String ) y → v { ( vec_clear [String] y ) }
    ~ x xs {
        ( f xs )
        ( nurl_println_int ( string_len x ) )
    }
    ^ 0
}
