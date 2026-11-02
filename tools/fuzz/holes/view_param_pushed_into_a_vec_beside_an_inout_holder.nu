// view_param_pushed_into_a_vec_beside_an_inout_holder: agora #370 — a callee pushes its view parameter into a Vec parameter that is not its first argument (an inout holder is)
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a callee pushes its view parameter into a Vec parameter that is not its first argument (an inout holder is)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w ( Vec s ) out s src → v { ( vec_push [s] out src ) }

@ main → i {
    : ~ W w @ W { `w literal` }
    : ( Vec s ) out ( vec_new [s] )
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( f w out ( string_data s ) )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
