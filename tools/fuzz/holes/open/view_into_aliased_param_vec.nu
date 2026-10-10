// OPEN in 0.72.0 — a view of a local stored through a Vec binding that aliases a parameter: the caller reads freed memory.
// `addl` binds `w` to its parameter `v` (the caller's Vec) and pushes `x`, a fresh string it releases
// when it returns. A ( Vec s ) holds views; the push of a local's view through the alias is not reported
// (nor is the direct push, view_into_param_container), and main reads element 0 after `x` was released.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading element 0.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ addl ( Vec s ) v → v { : s x ( nurl_str_cat `ab` `cd` ) : ( Vec s ) w v ( vec_push [s] w x ) }

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( addl v )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ( nurl_println `P50D-MARK` )
    ^ 0
}
