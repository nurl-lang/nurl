// second_field_viewer_read_after_the_first_took_the_field: two bindings read out of one field (`: R a . col res  : R b . col res`), one handed to a parameter that takes it, the other read after — accepted, a heap-use-after-free: consuming a field viewer takes the field over, and the other viewer keeps a copy of the handle its consumer freed (agora #271).
// Closed: a viewer that takes its field over ends every borrow of a path overlapping that field — another viewer of it, a viewer of a field of it (`. . col res v`), or of one holding it.
// main (before this PR): accepted; AddressSanitizer reports a heap-use-after-free in main.
// map: §7.6 | A2 | rejected | - | agora #271: a second viewer of one field, or of a field nested in it, read after the first took the field over (UAF)
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C col @ C { @ R { xs } 0 }
    : R a . col res
    : R b . col res
    ( nurl_println_int ( eat b ) )
    ^ ( vec_len [i] . a v )
}
