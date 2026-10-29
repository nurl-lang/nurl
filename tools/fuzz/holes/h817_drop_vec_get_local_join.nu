// H817: agora #187 — the same call as an arm of a returned `?` (drop_vec_get_local_join).
// Closed: A value that cannot be copied, handed back from a call that may lend it out of an argument this frame owns (a local, a `sink` parameter), is refused at module end on the callee's final summary — there is nothing to copy (__park_nc_local_lend / resolve_nc_local_lends; agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → ?D {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v @ D { ( string_from `element string long enough for a heap buffer` ) } )
    ^ ? c ( vec_get [D] v 0 ) @ ?D { F }
}

@ main → i {
    : ?D a ( pick T )
    ?? a { T d → ( nurl_println_int ( string_len . d s ) ) F → ( nurl_println `none` ) }
    ^ 0
}
