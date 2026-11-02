// closure_local_bound_from_its_parameter_pushed_into_a_capture: the same pushed into a captured Vec of views.
// Closed: inside a closure body, a view bound from a capture or a parameter of the closure that the walk cannot see into (`cv_`) is one too, so storing that local into a capture or the closure's `inout` parameter is refused as storing the source itself is (agora #332).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #332: the same pushed into a captured Vec of views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) out ( vec_new [s] )
    : ( @ v s ) put \ s p → v { : s t p ( vec_push [s] out t ) }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        ( put ( string_data b ) )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
