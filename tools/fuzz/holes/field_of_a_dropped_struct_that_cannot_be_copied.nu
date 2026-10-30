// field_of_a_dropped_struct_that_cannot_be_copied: a function handing back a field that cannot be copied (a `% Drop` value with no clone) out of a struct it made — `: Hold h @ Hold { … } ^ . h r` — returned the field while dropping `h`, field and all, on the way out: the caller got a released value. A field that can be copied is moved out or copied; this one was neither.
// Closed: handing back such a field of a struct the function drops, of a module global or of a closure's capture is rejected; a parameter's field stays a lend, and one read through a pointer is raw code's to vouch for.
// main (before this PR): ASan heap-use-after-free.
// map: §7.6 | A2 | rejected | h221 | return %Drop field of local struct that is dropped on the way out
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ mk → Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Hold h @ Hold { @ Res { v } 1 }
    ^ . h r
}

@ main → i {
    : Res a ( mk )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
