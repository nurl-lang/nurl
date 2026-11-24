// inout_field_handed_to_an_emptying_inout_by_a_wrapper: a wrapper hands only a field of its `inout` struct parameter to an `inout` handle parameter that may hand it to a `sink`. On that path the field is empty when the wrapper returns, and the caller pushed through it.
// Closed: the field the wrapper hands on is moved on some paths in the wrapper's own walk (AGORA-991), and an `inout` parameter handed back with a field possibly empty is refused there (agora #280).
// main's compiler: compiled with no `unsafe`; the push stored through the field's null data pointer (ASan: stack-overflow, the optimiser having taken the store for unreachable code).
// map: §7.6 | A2 | rejected | h980 | a wrapper hands a field of its inout struct to an emptying inout callee, and the caller pushes through the field
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v i n }

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ wrap inout R r i c → i { ^ ( g3 . r v c ) }

@ main → i {
    : ~ R x @ R { ( vec_new [i] ) 0 }
    ( nurl_println_int ( wrap x 1 ) )
    ( vec_push [i] . x v 2 )
    ^ 0
}
